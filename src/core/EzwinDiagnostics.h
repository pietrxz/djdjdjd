#pragma once
#import <Foundation/Foundation.h>

void EzwinStartDiagnostics(void);
void EzwinTraceCheckpoint(unsigned stage, const char *name);
NSString *EzwinDiagnosticsPath(void);
