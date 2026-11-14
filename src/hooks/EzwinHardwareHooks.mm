#include "hooks/EzwinHardwareHooks.h"
#include <mach/arm/thread_status.h>
#include <mach/ndr.h>
#include <mach/mig_errors.h>
#include <sys/sysctl.h>
#include <pthread.h>
#include <string.h>

static EzwinHardwareRoute active[16];
static size_t activeCount;
static mach_port_t exceptionPort;
static kern_return_t installResult = KERN_FAILURE;
static pthread_mutex_t installLock = PTHREAD_MUTEX_INITIALIZER;

bool EzwinRedirectHardwareState(const EzwinHardwareRoute *routes, size_t count,
    const uint32_t *oldState, uint32_t oldCount, uint32_t *newState, uint32_t *newCount) {
    if (!routes || !oldState || !newState || !newCount || oldCount != 68) return false;
    uintptr_t pc;
#if defined(__arm64__)
    arm_thread_state64_t old;
    memcpy(&old, oldState, sizeof(old));
    pc = arm_thread_state64_get_pc(old);
#else
    memcpy(&pc, (const uint8_t *)oldState + 0x100, 8);
#endif
    for (size_t i = 0; i < count; ++i) if (pc == routes[i].target) {
        memcpy(newState, oldState, 68 * 4);
#if defined(__arm64__)
        arm_thread_state64_t state;
        memcpy(&state, newState, sizeof(state));
        arm_thread_state64_set_pc_fptr(state, (void *)routes[i].replacement);
        memcpy(newState, &state, sizeof(state));
#else
        memcpy((uint8_t *)newState + 0x100, &routes[i].replacement, 8);
#endif
        *newCount = 68;
        return true;
    }
    return false;
}

// State-only Mach exceptions (2406) contain a variable-length code array followed by the register state.
bool EzwinHandleHardwareMessage(const mach_msg_header_t *request, mach_msg_header_t *reply,
    size_t capacity, const EzwinHardwareRoute *routes, size_t count) {
    if (!request || !reply || capacity < sizeof(mig_reply_error_t)) return false;
    mig_reply_error_t error = {};
    error.Head.msgh_bits = MACH_MSGH_BITS(MACH_MSGH_BITS_REMOTE(request->msgh_bits), 0);
    error.Head.msgh_remote_port = request->msgh_remote_port;
    error.Head.msgh_id = request->msgh_id + 100;
    error.Head.msgh_size = sizeof(error);
    error.NDR = NDR_record;
    error.RetCode = MIG_BAD_ID;
    if (request->msgh_id == 2406 && !(request->msgh_bits & MACH_MSGH_BITS_COMPLEX)) {
        error.RetCode = MIG_BAD_ARGUMENTS;
        const uint8_t *bytes = (const uint8_t *)request;
        const size_t prefix = sizeof(mach_msg_header_t) + sizeof(NDR_record_t);
        if (request->msgh_size >= prefix + 8) {
            int exception; uint32_t codes;
            memcpy(&exception, bytes + prefix, 4); memcpy(&codes, bytes + prefix + 4, 4);
            size_t stateHeader = prefix + 8 + codes * 8;
            if (codes <= 2 && request->msgh_size >= stateHeader + 8) {
                int flavor; uint32_t words;
                memcpy(&flavor, bytes + stateHeader, 4); memcpy(&words, bytes + stateHeader + 4, 4);
                size_t expected = stateHeader + 8 + words * 4;
                if (flavor == 6 && words == 68 && expected == request->msgh_size && exception == EXC_BREAKPOINT) {
#pragma pack(push, 4)
                    struct Reply { mach_msg_header_t head; NDR_record_t ndr; kern_return_t result;
                        int flavor; uint32_t words; uint32_t state[68]; };
#pragma pack(pop)
                    Reply output = {};
                    if (capacity >= sizeof(output)) {
                        uint32_t old[68]; memcpy(old, bytes + stateHeader + 8, sizeof(old));
                        if (EzwinRedirectHardwareState(routes, count, old, words, output.state, &output.words)) {
                            output.head = error.Head; output.head.msgh_size = sizeof(output);
                            output.ndr = NDR_record; output.result = KERN_SUCCESS; output.flavor = 6;
                            memcpy(reply, &output, sizeof(output));
                            return true;
                        }
                        error.RetCode = KERN_FAILURE;
                    }
                }
            }
        }
    }
    memcpy(reply, &error, sizeof(error));
    return true;
}

static void *exceptionLoop(void *argument) {
    mach_port_t port = (mach_port_t)(uintptr_t)argument;
    union Buffer { mach_msg_header_t head; uint8_t bytes[2048]; } request, reply;
    for (;;) {
        kern_return_t received = mach_msg(&request.head, MACH_RCV_MSG, 0, sizeof(request), port,
            MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
        if (received == MACH_RCV_PORT_DIED || received == MACH_RCV_INVALID_NAME) return nullptr;
        if (received != MACH_MSG_SUCCESS) continue;
        size_t count = __atomic_load_n(&activeCount, __ATOMIC_ACQUIRE);
        if (!EzwinHandleHardwareMessage(&request.head, &reply.head, sizeof(reply), active, count)) continue;
        mach_msg(&reply.head, MACH_SEND_MSG, reply.head.msgh_size, 0, MACH_PORT_NULL,
            MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL);
    }
    return nullptr;
}

kern_return_t EzwinInstallHardwareRoutes(const EzwinHardwareRoute *routes, size_t count) {
#if defined(__arm64__)
    if (!routes || !count || count > 16) return KERN_INVALID_ARGUMENT;
    pthread_mutex_lock(&installLock);
    if (activeCount) {
        bool same = count == activeCount && !memcmp(routes, active, count * sizeof(*routes));
        pthread_mutex_unlock(&installLock);
        return same ? installResult : KERN_ALREADY_IN_SET;
    }
    uint32_t capacity = 0; size_t capacitySize = sizeof(capacity);
    kern_return_t result = KERN_RESOURCE_SHORTAGE;
    if (sysctlbyname("hw.optional.breakpoint", &capacity, &capacitySize, nullptr, 0) || capacity < count) {
        pthread_mutex_unlock(&installLock); return result;
    }
    if (capacity > 16) capacity = 16;
    thread_act_array_t threads = nullptr; mach_msg_type_number_t threadCount = 0;
    result = task_threads(mach_task_self(), &threads, &threadCount);
    if (result != KERN_SUCCESS) { pthread_mutex_unlock(&installLock); return result; }
    uint32_t used = 0;
    arm_debug_state64_t defaults = {};
    mach_msg_type_number_t defaultWords = ARM_DEBUG_STATE64_COUNT;
    result = task_get_state(mach_task_self(), ARM_DEBUG_STATE64, (thread_state_t)&defaults, &defaultWords);
    if (result == KERN_SUCCESS) {
        for (unsigned slot = 0; slot < capacity; ++slot) if (defaults.__bcr[slot] & 1) used |= 1u << slot;
    } else defaults = {};
    // Some kernels expose per-thread debug state but do not return task defaults.
    result = KERN_SUCCESS;
    for (unsigned i = 0; i < threadCount && result == KERN_SUCCESS; ++i) {
        arm_debug_state64_t state = {}; mach_msg_type_number_t words = ARM_DEBUG_STATE64_COUNT;
        result = thread_get_state(threads[i], ARM_DEBUG_STATE64, (thread_state_t)&state, &words);
        if (result != KERN_SUCCESS) break;
        for (unsigned slot = 0; slot < capacity; ++slot) if (state.__bcr[slot] & 1) used |= 1u << slot;
    }
    unsigned slots[16], found = 0;
    for (unsigned slot = 0; slot < capacity && found < count; ++slot) if (!(used & (1u << slot))) slots[found++] = slot;
    if (result == KERN_SUCCESS && found != count) result = KERN_RESOURCE_SHORTAGE;
    if (result == KERN_SUCCESS && !exceptionPort) {
        mach_port_t port = MACH_PORT_NULL;
        result = mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port);
        if (result == KERN_SUCCESS) result = mach_port_insert_right(mach_task_self(), port, port, MACH_MSG_TYPE_MAKE_SEND);
        if (result == KERN_SUCCESS) {
            pthread_t server;
            if (pthread_create(&server, nullptr, exceptionLoop, (void *)(uintptr_t)port)) result = KERN_RESOURCE_SHORTAGE;
            else pthread_detach(server);
        }
        if (result == KERN_SUCCESS) result = task_set_exception_ports(mach_task_self(), EXC_MASK_BREAKPOINT,
            port, EXCEPTION_STATE | MACH_EXCEPTION_CODES, ARM_THREAD_STATE64);
        if (result == KERN_SUCCESS) exceptionPort = port;
        else if (port) {
            mach_port_mod_refs(mach_task_self(), port, MACH_PORT_RIGHT_RECEIVE, -1);
            mach_port_deallocate(mach_task_self(), port);
        }
    }
    if (result == KERN_SUCCESS) {
        memcpy(active, routes, count * sizeof(*routes));
        __atomic_store_n(&activeCount, count, __ATOMIC_RELEASE);
        for (size_t i = 0; i < count; ++i) { defaults.__bvr[slots[i]] = routes[i].target; defaults.__bcr[slots[i]] = 0x1e5; }
        result = task_set_state(mach_task_self(), ARM_DEBUG_STATE64, (thread_state_t)&defaults, ARM_DEBUG_STATE64_COUNT);
        for (unsigned i = 0; i < threadCount && result == KERN_SUCCESS; ++i) {
            arm_debug_state64_t state = {}; mach_msg_type_number_t words = ARM_DEBUG_STATE64_COUNT;
            result = thread_get_state(threads[i], ARM_DEBUG_STATE64, (thread_state_t)&state, &words);
            if (result != KERN_SUCCESS) break;
            for (size_t hook = 0; hook < count; ++hook) {
                state.__bvr[slots[hook]] = routes[hook].target; state.__bcr[slots[hook]] = 0x1e5;
            }
            result = thread_set_state(threads[i], ARM_DEBUG_STATE64, (thread_state_t)&state, ARM_DEBUG_STATE64_COUNT);
        }
        // Retain routes if installation is partial so every already-armed breakpoint remains serviceable.
    }
    for (unsigned i = 0; i < threadCount; ++i) mach_port_deallocate(mach_task_self(), threads[i]);
    vm_deallocate(mach_task_self(), (vm_address_t)threads, threadCount * sizeof(*threads));
    installResult = result;
    pthread_mutex_unlock(&installLock);
    return result;
#else
    (void)routes; (void)count;
    return KERN_NOT_SUPPORTED;
#endif
}
