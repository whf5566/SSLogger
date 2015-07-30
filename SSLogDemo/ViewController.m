//
//  ViewController.m
//  SSLogDemo
//
//  Created by weihuafeng on 15/4/7.
//  Copyright (c) 2015年 whf5566. All rights reserved.
//

#import "ViewController.h"
#import "SSLogger.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
   
    NSLog(@"log file is here \n %@/Library/Caches/SSLog/",NSHomeDirectory());
    
    // Delete log 7 days ago
    SSLoggerCleanLog([[NSDate date] dateByAddingTimeInterval:-60*60*24*7.0]);
    
    // Start log.
    SSLoggerStart();

    // Catch crash and log to file.
    SSLoggerCatchCrash();
    
    // Redirect NSLog to file.
//    SSLoggerRedirectNSLog();
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)uncaughtException:(id)sender
{
    NSMutableArray * a = [NSMutableArray array];
    [a objectAtIndex:2];
}

- (IBAction)loglog:(id)sender
{
    int i = 0;
    NSString* logStr = @"this is a str";
    
    NSMutableString * veryLenStr = [NSMutableString stringWithFormat:@""];
    for (int i; i< (1ul<<20); ++i) {
        [veryLenStr appendString:@"1"];
    }

    /* DLog is a macro .Print cpp fileName and */
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
    
    SSLog(@"Test SSLog");
    SSLog(nil);
    SSLog(@"");
    SSLog(@"  ");
    SSLog(@"",i);
    SSLog(@"%@",@"this is a format string");
    SSLog(@"%@",logStr);
    NSString* format1 = @"int %2d string :%@";
    // SSLog(format1); wrong  NSLog(format1);
    // SSLog(format1,i); wrong NSLog(format1,i);
    SSLog(format1,i,logStr);
    SSLog(@"%@",[NSDate date]);
    SSLog(@"%@",self);
    
    SSLog(veryLenStr);
    
}

- (IBAction)threadLog:(id)sender
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        for (int i=0; i<1000; ++i) {
            DLog(@"global_queue %d",i);
        }
    });
    
    for (int i = 0; i<1000; ++i) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            DLog(@"global_queue %d",i);
        });
    }
}

- (IBAction)cleanLog:(id)sender
{
    // Delete all log file
    SSLoggerCleanLog([NSDate distantFuture]);
}

@end
