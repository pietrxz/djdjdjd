#pragma once
#import <Foundation/Foundation.h>
typedef uint32_t (*EzwinFileProbeOriginal)(const char *path);
uint32_t EzwinFilterFileProbe(EzwinFileProbeOriginal original,const char *path);
void EzwinInstallSymbolHooks(void);
NSDictionary *EzwinSymbolHookStatus(void);
