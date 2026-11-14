#include "unity/EzwinOffsets1900.h"
#include "features/items/EzwinItemESP.h"
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

static uintptr_t pointer(uintptr_t address) { uintptr_t value; memcpy(&value,(void *)address,8); return value; }
static int integer(uintptr_t address) { int value; memcpy(&value,(void *)address,4); return value; }
static bool plausible(uintptr_t value) { return value>=0x10000 && value<0x1000000000000ULL && !(value&7); }
static bool overlaps(EzwinItemSample a, EzwinItemSample b) {
    return fabsf(a.screen.x-b.screen.x)<(a.width+b.width)*.5f &&
        fabsf(a.screen.y-b.screen.y)<(a.height+b.height)*.5f;
}
static int compare(const void *a,const void *b) {
    float x=((const EzwinItemSample *)a)->distance,y=((const EzwinItemSample *)b)->distance;
    return x<y?-1:x>y;
}
void EzwinCollectItems(EzwinItemState *state, uintptr_t context, EzwinPosition camera,
    const EzwinProjection *projection, const EzwinItemAPI *api) {
    if (!state) return; state->count=0;
    if (!plausible(context) || !projection || !projection->initialized || !api ||
        !api->valid || !api->transform || !api->matrix) return;
    uintptr_t registry=pointer(context+EzwinField_ContextItemRegistry),list=plausible(registry)?pointer(registry+EzwinField_ItemRegistryList):0;
    if (!plausible(list)) return;
    uintptr_t array=pointer(list+EzwinField_ItemListArray); int count=integer(list+EzwinField_ItemListCount);
    if (!plausible(array) || count<0 || count>4096 || count>integer(array+EzwinField_ArrayLength)) return;
    // udcops 0x273e4 walks 16-byte entries and reads each value at array+EzwinField_ItemEntryValue.
    for (int i=0;i<count;++i) {
        uintptr_t actor=pointer(array+EzwinField_ItemEntryValue+(uintptr_t)i*EzwinField_ItemEntryStride);
        if (!plausible(actor)) continue;
        uintptr_t definition=pointer(actor+EzwinField_ItemDefinition);
        int identifier=plausible(definition)?integer(definition+EzwinField_DefinitionIdentifier):0;
        uintptr_t component=pointer(actor+EzwinField_ItemComponent);
        if (identifier<=0 || !plausible(component) || !api->valid((void *)component)) continue;
        void *transform=api->transform((void *)component);
        if (!transform || !api->valid(transform)) continue;
        EzwinPosition world=EzwinMatrixPosition(api->matrix(transform));
        float distance=sqrtf((world.x-camera.x)*(world.x-camera.x)+(world.y-camera.y)*(world.y-camera.y)+
            (world.z-camera.z)*(world.z-camera.z));
        if (!isfinite(distance) || distance>150) continue;
        EzwinPosition screen=EzwinProjectPosition(projection,world);
        EzwinPosition up=EzwinProjectPosition(projection,{world.x,world.y+.4f,world.z});
        if (!(screen.z>0 && up.z>0) || !isfinite(screen.x) || !isfinite(screen.y)) continue;
        float height=fmaxf(5,fminf(28,fabsf(up.y-screen.y)*.5f)),width=height*3.25f;
        const char *name=api->weaponName?api->weaponName(identifier):nullptr;
        uintptr_t texture=api->icon&&name?api->icon(name,height,&width):0;
        width=width>0?fminf(width,height*3.5f):height*3.25f;
        EzwinItemSample sample={actor,texture,world,{screen.x,screen.y},distance,width,height,1,identifier,{}};
        snprintf(sample.label,sizeof(sample.label),"%s",name?:"Item");
        if (state->count<256) state->items[state->count++]=sample;
        else { int far=0; for(int j=1;j<256;++j)if(state->items[j].distance>state->items[far].distance)far=j;
            if(distance<state->items[far].distance)state->items[far]=sample; }
    }
    qsort(state->items,(size_t)state->count,sizeof(state->items[0]),compare);
    for(int i=0;i<state->count;++i) for(int j=0;j<i;++j)
        if(overlaps(state->items[i],state->items[j]))state->items[i].alpha=fmaxf(.2f,state->items[i].alpha*.4f);
}
void EzwinRenderItems(const EzwinItemState *state,const EzwinProjection *projection,uint32_t color) {
    if(!state || !projection) return;
    for(int i=0;i<state->count;++i) {
        EzwinItemSample item=state->items[i]; EzwinPosition screen=EzwinProjectPosition(projection,item.world);
        if(!(screen.z>0) || !isfinite(screen.x) || !isfinite(screen.y))continue;
        uint32_t tinted=(color&0xffffff)|((uint32_t)((color>>24)*item.alpha)<<24);
        if(item.texture) {
            EzwinDrawCommand image={};image.kind=10;image.x=screen.x-item.width*.5f;image.y=screen.y-item.height*.5f;
            image.right=image.x+item.width;image.bottom=image.y+item.height;image.color=tinted;image.content.texture=item.texture;
            EzwinQueueESPCommand(image);
        }
        EzwinDrawCommand text={};text.kind=7;text.x=screen.x;text.y=screen.y+item.height*.5f+2;text.color=tinted;
        if(item.texture)snprintf(text.content.text,sizeof(text.content.text),"%.0fm",item.distance);
        else snprintf(text.content.text,sizeof(text.content.text),"%.14s %.0fm",item.label,item.distance);
        EzwinQueueESPCommand(text);
    }
}
