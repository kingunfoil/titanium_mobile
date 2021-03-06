/**
 * Appcelerator Titanium Mobile
 * Copyright (c) 2009-2015 by Appcelerator, Inc. All Rights Reserved.
 * Licensed under the terms of the Apache Public License
 * Please see the LICENSE included with this distribution for details.
 */

#import "TiExceptionHandler.h"
#import "TiApp.h"
#import "TiBase.h"
#include <execinfo.h>

static void TiUncaughtExceptionHandler(NSException *exception);

static NSUncaughtExceptionHandler *prevUncaughtExceptionHandler = NULL;

@implementation TiExceptionHandler

@synthesize delegate = _delegate;

+ (TiExceptionHandler *)defaultExceptionHandler
{
  static TiExceptionHandler *defaultExceptionHandler;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    defaultExceptionHandler = [[self alloc] init];
    prevUncaughtExceptionHandler = NSGetUncaughtExceptionHandler();
    NSSetUncaughtExceptionHandler(&TiUncaughtExceptionHandler);
  });
  return defaultExceptionHandler;
}

- (void)reportException:(NSException *)exception
{
  NSArray *stackTrace = [exception callStackSymbols];
  NSString *message = [NSString stringWithFormat:
                                    @"[ERROR] The application has crashed with an uncaught exception '%@'.\nReason:\n%@\nStack trace:\n\n%@\n",
                                exception.name, exception.reason, [stackTrace componentsJoinedByString:@"\n"]];
  NSLog(@"%@", message);
  id<TiExceptionHandlerDelegate> currentDelegate = _delegate;
  if (currentDelegate == nil) {
    currentDelegate = self;
  }
  [currentDelegate handleUncaughtException:exception];
}

- (void)reportScriptError:(TiScriptError *)scriptError
{
  DebugLog(@"[ERROR] Script Error %@", [scriptError detailedDescription]);

  id<TiExceptionHandlerDelegate> currentDelegate = _delegate;
  if (currentDelegate == nil) {
    currentDelegate = self;
  }
  [currentDelegate handleScriptError:scriptError];
}

- (void)showScriptError:(TiScriptError *)error
{
  NSArray<NSString *> *exceptionStackTrace = [NSThread callStackSymbols];

  if (exceptionStackTrace == nil) {
    [[TiApp app] showModalError:[error description]];
    [[NSNotificationCenter defaultCenter] postNotificationName:kTiErrorNotification
                                                        object:self
                                                      userInfo:error.dictionaryValue];
  } else {
    NSMutableArray<NSString *> *formattedStackTrace = [[[NSMutableArray alloc] init] autorelease];
    NSUInteger exceptionStackTraceLength = [exceptionStackTrace count];

    // re-size stack trace and format results. Starting at index = 1 to not include showScriptError call
    for (NSInteger i = 1; i < (exceptionStackTraceLength >= 20 ? 20 : exceptionStackTraceLength); i++) {
      NSString *line = [self removeWhitespace:[exceptionStackTrace objectAtIndex:i]];

      // remove stack index
      line = [line substringFromIndex:[line rangeOfString:@" "].location + 1];

      [formattedStackTrace addObject:line];
    }

    NSString *stackTrace = [formattedStackTrace componentsJoinedByString:@"\n"];
    [[TiApp app] showModalError:[NSString stringWithFormat:@"%@\n\n%@", [error description], stackTrace]];
    NSMutableDictionary *errorDict = [error.dictionaryValue mutableCopy];
    [errorDict setObject:stackTrace forKey:@"stackTrace"];
    [[NSNotificationCenter defaultCenter] postNotificationName:kTiErrorNotification object:self userInfo:errorDict];
  }
}

- (NSString *)removeWhitespace:(NSString *)line
{
  while ([line rangeOfString:@"  "].length > 0) {
    line = [line stringByReplacingOccurrencesOfString:@"  " withString:@" "];
  }
  return line;
}

#pragma mark - TiExceptionHandlerDelegate

- (void)handleUncaughtException:(NSException *)exception
{
  [[TiApp app] showModalError:[NSString stringWithFormat:@"%@\n    %@", exception.reason, [[exception callStackSymbols] componentsJoinedByString:@"\n    "]]];
}

- (void)handleScriptError:(TiScriptError *)error
{
  [self showScriptError:error];
}

@end

@implementation TiScriptError

@synthesize message = _message;
@synthesize sourceURL = _sourceURL;
@synthesize lineNo = _lineNo;
@synthesize column = _column;
@synthesize dictionaryValue = _dictionaryValue;
@synthesize backtrace = _backtrace;

- (id)initWithMessage:(NSString *)message sourceURL:(NSString *)sourceURL lineNo:(NSInteger)lineNo
{
  self = [super init];
  if (self) {
    _message = [message copy];
    _sourceURL = [sourceURL copy];
    _lineNo = lineNo;
  }
  return self;
}

- (id)initWithDictionary:(NSDictionary *)dictionary
{
  NSString *message = [[dictionary objectForKey:@"message"] description];
  if (message == nil) {
    message = [[dictionary objectForKey:@"nativeReason"] description];
  }
  NSString *sourceURL = [[dictionary objectForKey:@"sourceURL"] description];
  NSInteger lineNo = [[dictionary objectForKey:@"line"] integerValue];

  self = [self initWithMessage:message sourceURL:sourceURL lineNo:lineNo];
  if (self) {
    _column = [[dictionary objectForKey:@"column"] integerValue];
    _backtrace = [[[dictionary objectForKey:@"backtrace"] description] copy];
    if (_backtrace == nil) {
      _backtrace = [[[dictionary objectForKey:@"stack"] description] copy];
    }
    _dictionaryValue = [dictionary copy];
  }
  return self;
}

- (void)dealloc
{
  RELEASE_TO_NIL(_message);
  RELEASE_TO_NIL(_sourceURL);
  RELEASE_TO_NIL(_backtrace);
  RELEASE_TO_NIL(_dictionaryValue);
  [super dealloc];
}

- (NSString *)description
{
  if (self.sourceURL != nil) {
    // attempt to load encrypted source code
    NSURL *sourceURL = [NSURL URLWithString:self.sourceURL];
    NSData *data = [TiUtils loadAppResource:sourceURL];
    NSString *source = nil;
    if (data == nil) {
      source = [NSString stringWithContentsOfFile:[sourceURL path] encoding:NSUTF8StringEncoding error:NULL];
    } else {
      source = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    }
    NSArray *lines = [source componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSString *line = [lines objectAtIndex:self.lineNo - 1];
    NSString *linePointer = [@"" stringByPaddingToLength:self.column withString:@" " startingAtIndex:0];

    // remove bundle path from source paths
    NSString *encodedBundlePath = [NSString stringWithFormat:@"file://%@", [[NSBundle mainBundle].bundlePath stringByReplacingOccurrencesOfString:@" " withString:@"%20"]];
    NSString *jsStack = [self.backtrace stringByReplacingOccurrencesOfString:encodedBundlePath withString:@""];

    return [NSString stringWithFormat:@"/%@:%ld\n%@\n%@^\n%@\n%@", [self.sourceURL lastPathComponent], (long)self.lineNo, line, linePointer, self.message, jsStack];
  } else {
    return [NSString stringWithFormat:@"%@", self.message];
  }
}

- (NSString *)detailedDescription
{
  return _dictionaryValue != nil ? [_dictionaryValue description] : [self description];
}

@end

//
// thanks to: http://www.restoroot.com/Blog/2008/10/18/crash-reporter-for-iphone-applications/
//
static void TiUncaughtExceptionHandler(NSException *exception)
{
  static BOOL insideException = NO;

  // prevent recursive exceptions
  if (insideException) {
    exit(1);
    return;
  }
  insideException = YES;

  [[TiExceptionHandler defaultExceptionHandler] reportException:exception];

  insideException = NO;
  if (prevUncaughtExceptionHandler != NULL) {
    prevUncaughtExceptionHandler(exception);
  }

  // exceptions on seperate threads can cause the application to terminate
  // if we let the thread continue
  if (![NSThread isMainThread]) {
    [NSThread exit];
  }
}
