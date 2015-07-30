# SSLogger
SSLogger是一个很简单的，轻量级的iOS日志记录工具。使用方法和NSLog类似，可以将日志信息记录到文件中；可以捕捉到程序崩溃信息并记录下来。

## Installation
将SSLogger.h SSLogger.m文件加入到工程中即可。

## Example
```objc
// 清除七天前的日志文件
SSLoggerCleanLog([[NSDate date] dateByAddingTimeInterval:-60*60*24*7.0]);
// 开始日志记录
SSLoggerStart();
// 捕捉到程序崩溃信息
SSLoggerCatchCrash();

NSString* logStr = @"this is a str";

NSMutableString * veryLenStr = [NSMutableString stringWithFormat:@""];
for (int i; i< (1ul<<20); ++i) {
[veryLenStr appendString:@"1"];
}

/* DLog is a macro .*/
DLog(@"Test DLog");
DLog(nil);
DLog(@"");
DLog(@"  ");
DLog(@"",i);
DLog(@"%@",@"this is a format string");
DLog(@"%@",logStr);
NSString* format = @"int %2d string :%@";
// DLog(format); wrong  NSLog(format);
// DLog(format,i); wrong NSLog(format,i);
DLog(format,i,logStr);

DLog(@"%@",[NSDate date]);
DLog(@"%@",self);
DLog(veryLenStr);
```

## License
All code is licensed under the BSD license. See the LICENSE file for more details.
