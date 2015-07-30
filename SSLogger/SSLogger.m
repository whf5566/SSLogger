/*
 * SSLogger.m
 *
 * version 1.0.1 23-MAR-2015 by whf5566@gmail.com
 *
 * https://github.com/whf5566/SSLogger.git
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

#import <execinfo.h>
#import <signal.h>
#import <pthread.h>
#import <libkern/OSAtomic.h>
#import <UIKit/UIKit.h>

#import "SSLogger.h"

#define SSLOG_TO_FILE       1
#define SSLOG_TO_CONSOLE    1

// #if TARGET_IPHONE_SIMULATOR
// #undef SSLOG_TO_FILE
// #define SSLOG_TO_FILE 1 // we don't want to write log to file on SIMULATOR
// #endif

#if SSLOG_TO_CONSOLE
  #define __NSLog(s, ...)   NSLog((s),##__VA_ARGS__)
#else
  #define __NSLog(s, ...)   do {} while (0)
#endif

#define kStrTimeFormat      @"yyyy-MM-dd HH:mm:ss.SSS"
#define kLogFileFormat      @"yyyy-MM-dd_HH.mm.ss.SSS"
#define kSSLoggerThreadName @"__$SSLoggerThreadName$__"

@interface NSDate (timeString)
- (NSString *)stringWithFormat:(NSString *)format;
@end

@implementation NSDate (timeString)

- (NSString *)stringWithFormat:(NSString *)format
{
    if ((format == nil) || (format.length == 0)) {
        return nil;
    }

    NSDateFormatter *dateFormatter = [[NSDateFormatter  alloc]  init];

    dateFormatter.dateFormat = format;
    return [dateFormatter stringFromDate:self];
}

@end

@interface LogMessage : NSObject
@property (nonatomic, assign) int32_t   seq;
@property (nonatomic, strong) NSDate    *time;
@property (nonatomic, copy) NSString  *threadName;
@property (nonatomic, copy) NSString  *message;

- (instancetype)initWithMessage:(NSString *)msg seq:(int32_t)seq;
- (NSString *)stringForWrite;
- (NSData *)dataForWrite;
@end

@implementation LogMessage

- (instancetype)initWithMessage:(NSString *)msg seq:(int32_t)seq
{
    self = [self init];

    if (self) {
        _seq = seq;
        _time = [NSDate date];
        _threadName = [LogMessage currentThreadName];
        _message = msg;
    }

    return self;
}

- (NSString *)stringForWrite
{
    return [NSString stringWithFormat:@"[%@][%@]%@\n", [_time stringWithFormat:kStrTimeFormat], _threadName, _message];
}

- (NSData *)dataForWrite
{
    return [[self stringForWrite] dataUsingEncoding:NSUTF8StringEncoding];
}

+ (NSString *)currentThreadName
{
    if ([NSThread isMainThread]) {
        return @"Main";
    }

    NSString *name = nil;

    if ([NSThread isMultiThreaded]) {
        NSThread *thread = [NSThread currentThread];
        name = [thread name];

        if ([name length] == 0) {
            NSMutableDictionary *threadDict = [thread threadDictionary];
            name = [threadDict objectForKey:kSSLoggerThreadName];

            if (name == nil) {
                name = [thread description];
                NSArray *prefixes = @[@"num = ", @"number = "];
                NSRange range = NSMakeRange(NSNotFound, 0);

                for (NSString *prefix in prefixes) {
                    range = [name rangeOfString:prefix];

                    if (range.location != NSNotFound) {
                        break;
                    }
                }

                if (range.location != NSNotFound) {
                    name = [name substringWithRange:NSMakeRange(range.location + range.length, [name length] - range.location - range.length - 1)];
                    name = [NSString stringWithFormat:@"%4ld", (long)[name integerValue]];
                    [threadDict setObject:name forKey:kSSLoggerThreadName];
                } else {
                    name = nil;
                }
            }
        }
    }

    if (name.length == 0) {
#if __LP64__
            int64_t pid = (int64_t)pthread_self();
            name = [NSString stringWithFormat:@"%lld", pid];
#else
            int32_t pid = (int32_t)pthread_self();
            name = [NSString stringWithFormat:@"%d", pid];
#endif
    }

    return name;
}

@end

@interface SSLogger () {
    NSThread            *_workerThread;
    volatile BOOL       _stopWorkerThread;
    CFRunLoopSourceRef  _logMessageRunLoopSource;
    CFRunLoopRef        _workRunLoopRef;

    NSLock          *_lockLogQueue;
    NSMutableArray  *_messageArray;
    int32_t         _messageSeq;  // the seq for next message

    NSOutputStream  *_writeStream;
    int32_t         _writeBytes;  // bytes written

    NSUncaughtExceptionHandler *_uncaughtExceptionHandler;
}
@property (nonatomic, copy) NSString          *currentLogFileName;
@property (nonatomic, copy) NSString          *nextLogFileName;
@property (nonatomic, strong) NSOutputStream    *writeStream;
@property (nonatomic, copy) NSString          *logDirectory; // default  Library/Data/SSLog/
@end

@implementation SSLogger
@synthesize logDirectory = _logDirectory, nextLogFileName = _nextLogFileName, writeStream = _writeStream;
+ (SSLogger *)shareManger
{
    __strong static SSLogger    *_singleton = nil;
    static dispatch_once_t      pred;

    dispatch_once(&pred, ^{
        _singleton = [[self alloc] init];
    });
    return _singleton;
}

- (instancetype)init
{
    self = [super init];

    if (self) {
        _logDirectory = [NSString stringWithFormat:@"%@/Library/Data/SSLog/", NSHomeDirectory()];
        _fileMaxSize = kfileMaxSize;
        _stopWorkerThread = NO;
        _lockLogQueue = [[NSLock alloc] init];
        _messageSeq = 0;
        _currentLogFileName = self.nextLogFileName;
        _writeStream = nil;
        _writeBytes = 0;
        _messageArray = [NSMutableArray array];
        _workerThread = nil;
        _uncaughtExceptionHandler = NULL;

        if (_logDirectory == nil) {
            return nil;
        }
    }

    return self;
}

- (void)start
{
    _stopWorkerThread = NO;

    if (_workerThread == nil) {
        _workerThread = [[NSThread alloc] initWithTarget:self selector:@selector(threadMain) object:nil];
        [_workerThread start];
        SSLog(@"SSLogger start");
    }
}

- (void)stop
{
    if (_workerThread) {
        SSLog(@"SSLogger stop");
        _stopWorkerThread = YES;
        _workerThread = nil;
    }
}

- (void)logMessage:(NSString *)str
{
    int32_t seq = OSAtomicIncrement32Barrier(&_messageSeq);

    LogMessage *msg = [[LogMessage alloc] initWithMessage:str seq:seq];

    if (!_stopWorkerThread) {
        [self performSelectorInBackground:@selector(pushMessageToQueue:) withObject:msg];
    }
}

- (void)pushMessageToQueue:(LogMessage *)msg
{
    if (msg == nil) {
        return;
    }

    [_lockLogQueue lock];
    int32_t     seq = msg.seq;
    NSUInteger  index = [_messageArray count];

    if (index) {
        LogMessage *lastMsg = nil;
        do {
            lastMsg = [_messageArray objectAtIndex:index - 1];
        } while (lastMsg.seq > seq && --index > 0);
    }

    [_messageArray insertObject:msg atIndex:index];
    [_lockLogQueue unlock];

    // Send signal
    if (_logMessageRunLoopSource) {
        CFRunLoopSourceSignal(_logMessageRunLoopSource);
    }
}

- (void)logFlush
{
    [self writeMessage];
}

- (void)writeMessage
{
    [_lockLogQueue lock];

    while (_messageArray.count) {
        NSData *data = [[_messageArray objectAtIndex:0] dataForWrite];

        if (data && (data.length > 0)) {
            NSUInteger  toWrite = data.length;
            uint8_t     *fp = (uint8_t *)data.bytes;
            NSUInteger  len = 0;

            while (_writeBytes + toWrite > _fileMaxSize) {
                len = [self.writeStream write:fp maxLength:_fileMaxSize - _writeBytes];
                fp += len;
                toWrite -= len;
                _writeBytes = 0;
                self.writeStream = nil;
            }

            len = [self.writeStream write:fp maxLength:toWrite];
            _writeBytes += len;
        }

        [_messageArray removeObjectAtIndex:0];
    }

    [_lockLogQueue unlock];
}

- (NSOutputStream *)writeStream
{
    if (_writeStream == nil) {
        self.currentLogFileName = self.nextLogFileName;
        NSString *filePath = [NSString stringWithFormat:@"%@%@", self.logDirectory, self.currentLogFileName];
        _writeStream = [[NSOutputStream alloc] initToFileAtPath:filePath append:YES];
        [_writeStream open];
        _writeBytes = 0;
    }

    return _writeStream;
}

- (void)setWriteStream:(NSOutputStream *)writeStream
{
    [_writeStream close];
    _writeStream = writeStream;
}

- (NSString *)nextLogFileName
{
    NSString *time = [[NSDate date] stringWithFormat:kLogFileFormat];

    _nextLogFileName = [NSString stringWithFormat:@"%@.log", time];
    static int index = 0;

    if ([self.currentLogFileName isEqualToString:_nextLogFileName]) {
        _nextLogFileName = [NSString stringWithFormat:@"%@_%02d.log", time, ++index];
    } else {
        index = 0;
    }

    return _nextLogFileName;
}

- (NSString *)nextLogFilePath
{
    return [NSString stringWithFormat:@"%@%@", self.logDirectory, self.nextLogFileName];
}

- (NSString *)logDirectory
{
    if (_logDirectory) {
        BOOL isDir = YES;

        if (![[NSFileManager defaultManager] fileExistsAtPath:_logDirectory isDirectory:&isDir]) {
            BOOL ret = [[NSFileManager defaultManager] createDirectoryAtPath:_logDirectory withIntermediateDirectories:YES attributes:nil error:nil];

            if (!ret) {
                //                NSLog(@"SSLogger logDirectory fail");
            }
        }
    }

    return _logDirectory;
}

#pragma mark log file manager
- (void)cleanLogBefore:(NSDate *)time
{
    if ([time isEqualToDate:[NSDate distantPast]]) {
        return;
    }

    BOOL deleteAll = [time isEqualToDate:[NSDate distantFuture]];

    NSString        *str = [time stringWithFormat:kLogFileFormat];
    NSString        *currentLogFile = self.currentLogFileName;
    NSMutableArray  *fileList = [self getLogFileNameList];

    for (NSString *fileName in fileList) {
        if ((deleteAll || (NSOrderedAscending == [fileName compare:str])) &&
            (![fileName isEqualToString:currentLogFile])) {
            [self deleteLogFile:fileName];
        }
    }
}

- (NSMutableArray *)getLogFileNameList
{
    NSMutableArray  *ret = [NSMutableArray arrayWithCapacity:10];
    NSString        *dirPath = self.logDirectory;
    NSArray         *tmplist = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dirPath error:nil];

    for (NSString *filename in tmplist) {
        NSString *fullpath = [dirPath stringByAppendingPathComponent:filename];

        if ([[filename pathExtension] isEqualToString:@"log"]) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:fullpath]) {
                [ret addObject:filename];
            }
        }
    }

    return [ret count] ? ret : nil;
}

- (void)deleteLogFile:(NSString *)filename
{
    if ((filename == nil) || (filename.length == 0)) {
        return;
    }

    NSString *fullPath = [self.logDirectory stringByAppendingPathComponent:filename];
    [[NSFileManager defaultManager] removeItemAtPath:fullPath error:NULL];
}

#pragma mark write thread
void RunLoopSourcePerformRoutine(void *info)
{
    if (info != NULL) {
        [(__bridge SSLogger *)info writeMessage];
    }
}

- (void)threadMain
{
    // add RunloopSource
    _logMessageRunLoopSource = [self addRunloopSource:((__bridge void *)self) perform:RunLoopSourcePerformRoutine];

    if (_logMessageRunLoopSource == NULL) {
        _stopWorkerThread = YES;
        return;
    }

    NSTimeInterval timeout = 0.10;

    while (!_stopWorkerThread) {
        @autoreleasepool {
            int result = CFRunLoopRunInMode(kCFRunLoopDefaultMode, timeout, true);

            if (result == kCFRunLoopRunHandledSource) {
                timeout = 0.0;
                continue;
            }

            if ((result == kCFRunLoopRunFinished) || (result == kCFRunLoopRunStopped)) {
                break;
            }

            timeout = fmax(1.0, fmin(0.10, timeout + 0.0005));
        }
    }

    // dispose RunloopSource
    [self disposeRunloopSource:&_logMessageRunLoopSource];

    [self logFlush]; // write log to file
}

- (CFRunLoopSourceRef)addRunloopSource:(void *)info perform:(void *)perform
{
    CFRunLoopSourceContext  context = {0, info, NULL, NULL, NULL, NULL, NULL, NULL, NULL, perform};
    CFRunLoopSourceRef      sourceRef = CFRunLoopSourceCreate(NULL, 0, &context);

    if (sourceRef != NULL) {
        CFRunLoopAddSource(CFRunLoopGetCurrent(), sourceRef, kCFRunLoopDefaultMode);
    }

    return sourceRef;
}

- (void)disposeRunloopSource:(CFRunLoopSourceRef *)sourceRef
{
    if (*sourceRef != NULL) {
        CFRunLoopSourceInvalidate(*sourceRef);
        CFRelease(*sourceRef);
        *sourceRef = NULL;
    }
}

#pragma mark NSLog
- (void)redirectNSLog
{
    if (isatty(STDOUT_FILENO)) {
        return;
    }

    NSString *logFilePath = self.nextLogFilePath;

    freopen([logFilePath cStringUsingEncoding:NSASCIIStringEncoding], "a+", stdout);
    freopen([logFilePath cStringUsingEncoding:NSASCIIStringEncoding], "a+", stderr);
}

#pragma mark CrashLog
- (void)catchCrashLog
{
    [[SSLogger shareManger] catchExceptionCrashLog];
    [[SSLogger shareManger] catchSignalCrash];
}

static void UncaughtExceptionHandler(NSException *exception);

- (void)catchExceptionCrashLog
{
    if (_uncaughtExceptionHandler == NULL) {
        _uncaughtExceptionHandler = NSGetUncaughtExceptionHandler();
        NSSetUncaughtExceptionHandler(&UncaughtExceptionHandler);
        [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(cancelCatchExceptionCrashLog)
        name    :UIApplicationWillTerminateNotification
        object  :nil];
    }
}

- (void)cancelCatchExceptionCrashLog
{
    if (_uncaughtExceptionHandler != NULL) {
        NSSetUncaughtExceptionHandler(_uncaughtExceptionHandler);
        _uncaughtExceptionHandler = NULL;
        [[NSNotificationCenter defaultCenter] removeObserver:self];
    }
}

static void signalCrashHandler(int sig, siginfo_t *info, void *context);

- (void)catchSignalCrash
{
    struct sigaction mySigAction;

    mySigAction.sa_sigaction = signalCrashHandler;
    mySigAction.sa_flags = SA_SIGINFO;

    sigemptyset(&mySigAction.sa_mask);
    sigaction(SIGQUIT, &mySigAction, NULL);
    sigaction(SIGILL, &mySigAction, NULL);
    sigaction(SIGTRAP, &mySigAction, NULL);
    sigaction(SIGABRT, &mySigAction, NULL);
    sigaction(SIGEMT, &mySigAction, NULL);
    sigaction(SIGFPE, &mySigAction, NULL);
    sigaction(SIGBUS, &mySigAction, NULL);
    sigaction(SIGSEGV, &mySigAction, NULL);
    sigaction(SIGSYS, &mySigAction, NULL);
    sigaction(SIGPIPE, &mySigAction, NULL);
    sigaction(SIGALRM, &mySigAction, NULL);
    sigaction(SIGXCPU, &mySigAction, NULL);
    sigaction(SIGXFSZ, &mySigAction, NULL);
}

@end

#pragma mark crashLog Handler
static bool __hasCaughtCrash = NO;
static void UncaughtExceptionHandler(NSException *exception)
{
    if (exception == nil) {
        return;
    }

    NSString        *name = [exception name];
    NSString        *reason = [exception reason];
    NSArray         *symbols = [exception callStackSymbols];
    NSMutableString *strSymbols = [[NSMutableString alloc] init];

    for (NSString *item in symbols) {
        [strSymbols appendString:@"\t"];
        [strSymbols appendString:item];
        [strSymbols appendString:@"\r\n"];
    }

    NSString    *logFilePath = [[SSLogger shareManger].nextLogFilePath stringByAppendingString:@"_Crash.log"];
    NSString    *time = [[NSDate date] stringWithFormat:kStrTimeFormat];
    NSString    *crashLog = [NSString stringWithFormat:@"[%@]*** Terminating app due to uncaught exception '%@', reason: '%@'\n*** First throw call stack:\n(\n%@)", time, name, reason, strSymbols];

    __hasCaughtCrash = [crashLog writeToFile:logFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static void signalCrashHandler(int sig, siginfo_t *info, void *context)
{
    if (__hasCaughtCrash) {
        return;
    }

    NSMutableString *str = [NSMutableString string];

    [str appendString:@"Stack:\n"];
    void    *callstack[128];
    int     frames = backtrace(callstack, 128);
    char    **strs = backtrace_symbols(callstack, frames);

    for (int i = 0; i < frames; ++i) {
        [str appendFormat:@"%s\n", strs[i]];
    }

    NSString *logFilePath = [[SSLogger shareManger].nextLogFilePath stringByAppendingString:@"_Crash.log"];
    [str writeToFile:logFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

#pragma mark SSLog API

void SSLog(NSString *format, ...)
{
#if SSLOG_TO_FILE || SSLOG_TO_CONSOLE
        va_list args;

        va_start(args, format);

        NSString *msgString = nil;

        if (format != nil) {
            msgString = [[NSString alloc] initWithFormat:format arguments:args];
        }

        va_end(args);
  #if SSLOG_TO_FILE
            [[SSLogger shareManger] logMessage:msgString];
  #endif

  #if SSLOG_TO_CONSOLE
            NSLog(@"%@", msgString);
  #endif
#endif
}

void SSLoggerStart()
{
    [[SSLogger shareManger] start];
}

void SSLoggerStop()
{
    [[SSLogger shareManger] stop];
}

void SSLoggerCleanLog(NSDate *time)
{
    [[SSLogger shareManger] cleanLogBefore:time];
}

void SSLoggerCatchCrash()
{
    [[SSLogger shareManger] catchCrashLog];
}

void SSLoggerRedirectNSLog()
{
    [[SSLogger shareManger] redirectNSLog];
}