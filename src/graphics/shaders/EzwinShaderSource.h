#pragma once
#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
const char *EzwinMetalCommon(void);
const char *EzwinMetalPlayerFragment(void);
const char *EzwinMetalPlayerVertex(void);
NSString *EzwinMetalSource(NSString *asset, BOOL vertex);
const char *EzwinMetalViewmodelFragment(void);
const char *EzwinMetalViewmodelVertex(void);
const char *EzwinMetalGlowVertex(void);
const char *EzwinMetalGlowFragment(void);
const char *EzwinMetalBloomVertex(void);
const char *EzwinMetalBloomFragment(void);
const char *EzwinMetalSkyVertex(void);
const char *EzwinMetalSkyFragment(void);

#ifdef __cplusplus
}
#endif
