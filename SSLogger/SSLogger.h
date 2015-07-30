/*
 * SSLogger.h
 *
 * version 0.0.1 23-MAR-2015 by whf5566@gmail.com
 *
 * BSD license follows (http://www.opensource.org/licenses/bsd-license.php)
 *
 * Copyright (c) 2010-2014 Florent Pillet All Rights Reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * Redistributions of  source code  must retain  the above  copyright notice,
 * this list of  conditions and the following  disclaimer. Redistributions in
 * binary  form must  reproduce  the  above copyright  notice,  this list  of
 * conditions and the following disclaimer  in the documentation and/or other
 * materials  provided with  the distribution.  Neither the  name of  Florent
 * Pillet nor the names of its contributors may be used to endorse or promote
 * products  derived  from  this  software  without  specific  prior  written
 * permission.  THIS  SOFTWARE  IS  PROVIDED BY  THE  COPYRIGHT  HOLDERS  AND
 * CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT
 * NOT LIMITED TO, THE IMPLIED  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A  PARTICULAR PURPOSE  ARE DISCLAIMED.  IN  NO EVENT  SHALL THE  COPYRIGHT
 * HOLDER OR  CONTRIBUTORS BE  LIABLE FOR  ANY DIRECT,  INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY,  OR CONSEQUENTIAL DAMAGES (INCLUDING,  BUT NOT LIMITED
 * TO, PROCUREMENT  OF SUBSTITUTE GOODS  OR SERVICES;  LOSS OF USE,  DATA, OR
 * PROFITS; OR  BUSINESS INTERRUPTION)  HOWEVER CAUSED AND  ON ANY  THEORY OF
 * LIABILITY,  WHETHER  IN CONTRACT,  STRICT  LIABILITY,  OR TORT  (INCLUDING
 * NEGLIGENCE  OR OTHERWISE)  ARISING  IN ANY  WAY  OUT OF  THE  USE OF  THIS
 * SOFTWARE,   EVEN  IF   ADVISED  OF   THE  POSSIBILITY   OF  SUCH   DAMAGE.
 *
 */
#import <Foundation/NSObject.h>

#define DLog(format, ...) do {SSLog(@"[%@:%d]%@", [[NSString stringWithUTF8String:__FILE__] lastPathComponent], __LINE__, (format) ? ([NSString stringWithFormat : (format), ##__VA_ARGS__]) : @"(null)"); } while (0)

#define kfileMaxSize (1ul << 20) // log files max size

#pragma mark SSLogger API

#ifdef __cplusplus
    extern "C" {
#endif

/**
 *  Start the log thread.
 */
extern void SSLoggerStart();

/**
 *  Stop the log thread.
 */
extern void SSLoggerStop();

/**
 *  Delete log file before the date
 */
extern void SSLoggerCleanLog(NSDate *time);

/**
 *  Redirect NSLog to file. Do not need SSLoggerStart()
 */
extern void SSLoggerRedirectNSLog();

/**
 *  Catch crash info and write to file. Do not need SSLoggerStart()
 */
extern void SSLoggerCatchCrash();

/**
 *  Log string to file.
 *  Notice:this function only work after SSLoggerStart()
 *         and not work after SSLoggerStop()
 */
extern void SSLog(NSString *format, ...)  NS_FORMAT_FUNCTION(1, 2);

#ifdef __cplusplus
    }
#endif

#pragma mark SSLogger class
@interface SSLogger : NSObject
+ (SSLogger *)shareManger;

@property (nonatomic, assign) NSInteger fileMaxSize;    // default 1<<20

- (void)logMessage:(NSString *)str;

- (void)start;
- (void)stop;

- (void)catchCrashLog;
- (void)redirectNSLog;

@end