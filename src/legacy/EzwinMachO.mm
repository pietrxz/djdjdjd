#import "legacy/EzwinHooks.h"
#include <string.h>
#include <stdlib.h>

static void MachOError(NSString *reason) __attribute__((noreturn));
static void MachOError(NSString *reason) {
    @throw [NSException exceptionWithName:@"EzwinMachO" reason:reason userInfo:nil];
}
static void CheckRange(NSData *data, uint64_t offset, uint64_t length) {
    if (offset > data.length || length > data.length - offset) MachOError(@"Truncated Mach-O data");
}
static uint32_t Read32(NSData *data, uint64_t offset) {
    CheckRange(data, offset, 4); uint32_t value; memcpy(&value, (const uint8_t *)data.bytes + offset, 4); return value;
}
static uint64_t Read64(NSData *data, uint64_t offset) {
    CheckRange(data, offset, 8); uint64_t value; memcpy(&value, (const uint8_t *)data.bytes + offset, 8); return value;
}
static NSString *ReadString(NSData *data, uint64_t offset) {
    CheckRange(data, offset, 1);
    const char *start = (const char *)data.bytes + offset;
    const char *end = (const char *)memchr(start, 0, data.length - offset);
    if (!end) MachOError(@"Unterminated Mach-O string");
    NSString *text = [[NSString alloc] initWithBytes:start length:end - start encoding:NSUTF8StringEncoding];
    if (!text) MachOError(@"Invalid UTF-8 symbol name");
    return text;
}
static uint64_t FileOffset(NSMutableDictionary *image, uint64_t rva, size_t length) {
    NSData *bytes = image[@"bytes"];
    for (NSDictionary *segment in image[@"segments"]) {
        uint64_t start = [segment[@"rva"] unsignedLongLongValue];
        uint64_t size = [segment[@"fileSize"] unsignedLongLongValue];
        if (rva < start || rva - start > size || length > size - (rva - start)) continue;
        uint64_t offset = [segment[@"fileOffset"] unsignedLongLongValue] + rva - start;
        CheckRange(bytes, offset, length);
        return offset;
    }
    MachOError(@"RVA is outside the file-backed segment");
}
uint64_t Ezwin_Address(uint64_t base, uint64_t rva) {
    if (rva > UINT64_MAX - base) MachOError(@"Address overflow");
    return base + rva;
}
static int HexDigit(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}
NSInteger Ezwin_ScanPattern(const uint8_t *data, size_t size, const char *pattern) {
    size_t length = strlen(pattern), count = 0;
    int *tokens = (int *)calloc(length + 1, sizeof(int));
    if (!tokens) MachOError(@"Could not allocate signature memory");
    for (size_t i = 0; i < length; i++) {
        if (pattern[i] == '?') tokens[count++] = -1;
        else if (HexDigit(pattern[i]) >= 0 && i + 1 < length && HexDigit(pattern[i + 1]) >= 0) {
            tokens[count++] = HexDigit(pattern[i]) * 16 + HexDigit(pattern[i + 1]); i++;
        }
    }
    NSInteger result = -1;
    if (count && count <= size) {
        for (size_t i = 0; i <= size - count; i++) {
            BOOL match = YES;
            for (size_t j = 0; j < count; j++) {
                if (tokens[j] >= 0 && tokens[j] != data[i + j]) { match = NO; break; }
            }
            if (match) { result = (NSInteger)i; break; }
        }
    }
    free(tokens);
    return result;
}
NSMutableDictionary *Ezwin_LoadMachO(NSString *path, uint64_t base,
    uint64_t (*resolve)(const char *, void *), void *context) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length < 32) MachOError(@"Could not read the Mach-O file or its header is too short");
    if (Read32(data, 0) != 0xfeedfacf || Read32(data, 4) != 0x0100000c)
        MachOError(@"A thin little-endian ARM64 Mach-O is required");
    NSMutableArray *segments = [NSMutableArray array];
    NSMutableArray *imports = [NSMutableArray array];
    NSMutableDictionary *pointers = [NSMutableDictionary dictionary];
    NSMutableDictionary *image = [@{@"bytes":data, @"base":@(base), @"fileType":@(Read32(data,12)),
        @"segments":segments, @"imports":imports, @"pointers":pointers} mutableCopy];
    uint64_t command = 32, commandsEnd = 32ULL + Read32(data,20), fixups = 0;
    CheckRange(data, 0, commandsEnd);
    for (uint32_t i = 0; i < Read32(data,16); i++) {
        uint32_t kind = Read32(data,command), size = Read32(data,command + 4);
        if (size < 8 || command > commandsEnd || size > commandsEnd - command) MachOError(@"Invalid load command");
        if (kind == 25) {
            if (size < 72) MachOError(@"Segment command is too short");
            const char *name = (const char *)data.bytes + command + 8;
            NSString *segmentName = [[NSString alloc] initWithBytes:name length:strnlen(name,16) encoding:NSUTF8StringEncoding];
            if (!segmentName) MachOError(@"Invalid segment name");
            [segments addObject:@{@"name":segmentName, @"rva":@(Read64(data,command+24)),
                @"size":@(Read64(data,command+32)), @"fileOffset":@(Read64(data,command+40)),
                @"fileSize":@(Read64(data,command+48))}];
        } else if (kind == 0x80000034) {
            if (size < 16) MachOError(@"Fixup command is too short");
            fixups = Read32(data,command+8); CheckRange(data,fixups,Read32(data,command+12));
        }
        command += size;
    }
    if (!fixups || Read32(data,fixups+20) != 1 || Read32(data,fixups+24) != 0)
        MachOError(@"This sample requires chained-import format 1");
    uint64_t starts = fixups + Read32(data,fixups+4);
    uint64_t importTable = fixups + Read32(data,fixups+8), names = fixups + Read32(data,fixups+12);
    uint32_t importCount = Read32(data,fixups+16);
    if (importCount > data.length / 4) MachOError(@"Invalid import count");
    NSMutableArray *importNames = [NSMutableArray array];
    for (uint32_t i = 0; i < importCount; i++)
        [importNames addObject:ReadString(data,names + (Read32(data,importTable+i*4) >> 9))];
    uint32_t segmentCount = Read32(data,starts);
    if (segmentCount > segments.count) MachOError(@"Invalid fixup segment count");
    for (uint32_t s = 0; s < segmentCount; s++) {
        uint32_t relative = Read32(data,starts+4+s*4);
        if (!relative) continue;
        uint64_t at = starts + relative;
        uint32_t format = Read32(data,at+4), pageSize = format & 0xffff;
        uint64_t segmentRva = Read64(data,at+8);
        uint32_t pages = Read32(data,at+20) & 0xffff;
        if ((format >> 16) != 6 || !pageSize) MachOError(@"DYLD_CHAINED_PTR_64_OFFSET is required");
        for (uint32_t page = 0; page < pages; page++) {
            uint16_t start; uint64_t entry = at + 22 + page*2;
            CheckRange(data,entry,2); memcpy(&start,(const uint8_t *)data.bytes+entry,2);
            if (start == 0xffff) continue;
            if (start & 0x8000) MachOError(@"Multi-start pages are not supported for this sample");
            uint64_t rva = segmentRva + (uint64_t)page*pageSize + start;
            while (YES) {
                uint64_t word = Read64(data,FileOffset(image,rva,8));
                uint64_t next = ((word >> 51) & 0xfff)*4, value;
                if (word >> 63) {
                    uint64_t ordinal = word & 0xffffff;
                    if (ordinal >= importNames.count) MachOError(@"Invalid import ordinal");
                    NSString *name = importNames[ordinal];
                    int8_t addend = (int8_t)((word >> 24) & 0xff);
                    value = resolve(name.UTF8String,context) + (int64_t)addend;
                    [imports addObject:[@{@"name":name,@"slot":@(rva),@"value":@(value)} mutableCopy]];
                } else value = Ezwin_Address(base,word & ((1ULL<<36)-1));
                pointers[@(rva)] = @(value);
                if (!next) break;
                rva = Ezwin_Address(rva,next);
            }
        }
    }
    return image;
}
uint64_t Ezwin_ReadPointer(NSMutableDictionary *image, uint64_t slot) {
    NSNumber *value = image[@"pointers"][@(slot)];
    return value ? value.unsignedLongLongValue : Read64(image[@"bytes"],FileOffset(image,slot,8));
}
void Ezwin_WritePointer(NSMutableDictionary *image, uint64_t slot, uint64_t value) {
    (void)FileOffset(image,slot,8);
    NSMutableDictionary *pointers = image[@"pointers"];
    pointers[@(slot)] = @(value);
    for (NSMutableDictionary *import in image[@"imports"])
        if ([import[@"slot"] unsignedLongLongValue] == slot) import[@"value"] = @(value);
}
NSInteger Ezwin_ScanUnityText(NSMutableDictionary *image, const char *pattern) {
    NSData *data = image[@"bytes"];
    for (NSDictionary *segment in image[@"segments"]) {
        if (![segment[@"name"] isEqualToString:@"__TEXT"]) continue;
        uint64_t rva = [segment[@"rva"] unsignedLongLongValue];
        uint64_t size = [segment[@"fileSize"] unsignedLongLongValue];
        NSInteger offset = Ezwin_ScanPattern((const uint8_t *)data.bytes + FileOffset(image,rva,size),size,pattern);
        return offset >= 0 ? (NSInteger)rva + offset : -1;
    }
    return -1;
}
