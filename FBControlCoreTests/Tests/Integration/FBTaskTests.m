/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>

#import "FBControlCoreFixtures.h"
#import "FBControlCoreLoggerDouble.h"

@interface FBTaskBuilder (FBTaskTests)

@end

@implementation FBTaskBuilder (FBTaskTests)

- (FBTask *)startSynchronously
{
  FBFuture<FBTask *> *future = [self start];
  NSError *error = nil;
  FBTask *task = [future await:&error];
  NSAssert(task, @"Task Could not be started %@", error);
  return task;
}

@end

@interface FBTaskTests : XCTestCase

@end

@implementation FBTaskTests

- (FBTask *)runAndWaitForTaskFuture:(FBFuture *)future
{
  [[future timeout:FBControlCoreGlobalConfiguration.regularTimeout waitingFor:@"FBTask to complete"] await:NULL];
  return future.result;
}

- (void)testTrueExit
{
  FBFuture *futureTask = [[[FBTaskBuilder
    withLaunchPath:@"/bin/sh" arguments:@[@"-c", @"true"]]
    withTaskLifecycleLoggingTo:FBControlCoreGlobalConfiguration.defaultLogger]
    runUntilCompletionWithAcceptableExitCodes:nil];

  FBTask *task = [self runAndWaitForTaskFuture:futureTask];

  XCTAssertEqualObjects(task.exitCode.result, @0);
}

- (void)testFalseExit
{
  FBFuture *futureTask = [[FBTaskBuilder
    withLaunchPath:@"/bin/sh" arguments:@[@"-c", @"false"]]
    runUntilCompletionWithAcceptableExitCodes:[NSSet setWithObject:@1]];

  FBTask *task = [self runAndWaitForTaskFuture:futureTask];
  XCTAssertEqualObjects(task.exitCode.result, @1);
}

- (void)testFalseExitWithStatusCodeError
{
  NSError *error = nil;
  id result = [[[FBTaskBuilder
    withLaunchPath:@"/bin/sh" arguments:@[@"-c", @"false"]]
    runUntilCompletionWithAcceptableExitCodes:[NSSet setWithObject:@0]]
    await:&error];

  XCTAssertNil(result);
  XCTAssertNotNil(error);
}

- (void)testEnvironment
{
  NSDictionary<NSString *, NSString *> *environment = @{
    @"FOO0": @"BAR0",
    @"FOO1": @"BAR1",
    @"FOO2": @"BAR2",
    @"FOO3": @"BAR3",
    @"FOO4": @"BAR4",
  };
  FBFuture *futureTask = [[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/env"]
    withEnvironment:environment]
    runUntilCompletionWithAcceptableExitCodes:nil];

  FBTask *task = [self runAndWaitForTaskFuture:futureTask];
  XCTAssertEqualObjects(task.exitCode.result, @0);
  for (NSString *key in environment.allKeys) {
    NSString *expected = [NSString stringWithFormat:@"%@=%@", key, environment[key]];
    XCTAssertTrue([task.stdOut containsString:expected]);
  }
}

- (void)testBase64Matches
{
  NSString *filePath = FBControlCoreFixtures.assetsdCrashPathWithCustomDeviceSet;
  NSString *expected = [[NSData dataWithContentsOfFile:filePath] base64EncodedStringWithOptions:0];

  FBFuture *futureTask = [[FBTaskBuilder
    withLaunchPath:@"/usr/bin/base64" arguments:@[@"-i", filePath]]
    runUntilCompletionWithAcceptableExitCodes:nil];
  FBTask *task = [self runAndWaitForTaskFuture:futureTask];

  XCTAssertEqual(task.statLoc.state, FBFutureStateDone);
  XCTAssertEqual(task.exitCode.state, FBFutureStateDone);
  XCTAssertEqual(task.signal.state, FBFutureStateFailed);
  XCTAssertEqualObjects(task.stdOut, expected);
  XCTAssertGreaterThan(task.processIdentifier, 1);
}

- (void)testStringsOfCurrentBinary
{
  NSString *bundlePath = [[NSBundle bundleForClass:self.class] bundlePath];
  NSString *binaryName = [[bundlePath lastPathComponent] stringByDeletingPathExtension];
  NSString *binaryPath = [[bundlePath stringByAppendingPathComponent:@"Contents/MacOS"] stringByAppendingPathComponent:binaryName];

  FBFuture *futureTask = [[FBTaskBuilder
    withLaunchPath:@"/usr/bin/strings" arguments:@[binaryPath]]
    runUntilCompletionWithAcceptableExitCodes:nil];
  FBTask *task = [self runAndWaitForTaskFuture:futureTask];


  XCTAssertEqual(task.statLoc.state, FBFutureStateDone);
  XCTAssertEqual(task.exitCode.state, FBFutureStateDone);
  XCTAssertEqual(task.signal.state, FBFutureStateFailed);
  XCTAssertTrue([task.stdOut containsString:NSStringFromSelector(_cmd)]);
  XCTAssertGreaterThan(task.processIdentifier, 1);
}

- (void)testBundleContents
{
  NSBundle *bundle = [NSBundle bundleForClass:self.class];
  NSString *resourcesPath = [[bundle bundlePath] stringByAppendingPathComponent:@"Contents/Resources"];

  FBFuture *futureTask = [[FBTaskBuilder
    withLaunchPath:@"/bin/ls" arguments:@[@"-1", resourcesPath]]
    runUntilCompletionWithAcceptableExitCodes:nil];
  FBTask *task = [self runAndWaitForTaskFuture:futureTask];

  XCTAssertEqual(task.statLoc.state, FBFutureStateDone);
  XCTAssertEqual(task.exitCode.state, FBFutureStateDone);
  XCTAssertEqual(task.signal.state, FBFutureStateFailed);
  XCTAssertGreaterThan(task.processIdentifier, 1);

  NSArray<NSString *> *fileNames = [task.stdOut componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
  XCTAssertGreaterThanOrEqual(fileNames.count, 2u);

  for (NSString *fileName in fileNames) {
    NSString *path = [bundle pathForResource:fileName ofType:nil];
    XCTAssertNotNil(path);
  }
}

- (void)testLineReader
{
  NSString *filePath = FBControlCoreFixtures.assetsdCrashPathWithCustomDeviceSet;
  NSMutableArray<NSString *> *lines = [NSMutableArray array];

  FBFuture *futureTask = [[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/grep" arguments:@[@"CoreFoundation", filePath]]
    withStdOutLineReader:^(NSString *line) {
      [lines addObject:line];
    }]
    runUntilCompletionWithAcceptableExitCodes:nil];
  FBTask *task = [self runAndWaitForTaskFuture:futureTask];

  XCTAssertEqual(task.statLoc.state, FBFutureStateDone);
  XCTAssertEqual(task.exitCode.state, FBFutureStateDone);
  XCTAssertEqual(task.signal.state, FBFutureStateFailed);
  XCTAssertTrue([task.stdOut conformsToProtocol:@protocol(FBDataConsumer)]);
  XCTAssertGreaterThan(task.processIdentifier, 1);

  [[FBFuture.empty delay:2] await:nil];
  XCTAssertEqual(lines.count, 8u);
  XCTAssertEqualObjects(lines[0], @"0   CoreFoundation                      0x0138ba14 __exceptionPreprocess + 180");
}

- (void)testLogger
{
  NSString *bundlePath = [[NSBundle bundleForClass:self.class] bundlePath];

  FBFuture *futureTask = [[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/file" arguments:@[bundlePath]]
    withStdErrToLogger:[FBControlCoreLoggerDouble new]]
    withStdOutToLogger:[FBControlCoreLoggerDouble new]]
    runUntilCompletionWithAcceptableExitCodes:nil];
  FBTask *task = [self runAndWaitForTaskFuture:futureTask];

  XCTAssertEqual(task.statLoc.state, FBFutureStateDone);
  XCTAssertEqual(task.exitCode.state, FBFutureStateDone);
  XCTAssertEqual(task.signal.state, FBFutureStateFailed);
  XCTAssertTrue([task.stdOut isKindOfClass:FBControlCoreLoggerDouble.class]);
  XCTAssertTrue([task.stdErr isKindOfClass:FBControlCoreLoggerDouble.class]);
}

- (void)testDevNull
{
  NSString *bundlePath = [[NSBundle bundleForClass:self.class] bundlePath];

  FBFuture *futureTask = [[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/file" arguments:@[bundlePath]]
    withStdOutToDevNull]
    withStdErrToDevNull]
    runUntilCompletionWithAcceptableExitCodes:nil];
  FBTask *task = [self runAndWaitForTaskFuture:futureTask];

  XCTAssertEqual(task.statLoc.state, FBFutureStateDone);
  XCTAssertEqual(task.exitCode.state, FBFutureStateDone);
  XCTAssertEqual(task.signal.state, FBFutureStateFailed);
  XCTAssertNil(task.stdOut);
  XCTAssertNil(task.stdErr);
}

- (void)testUpdatesStateWithAsynchronousTermination
{
  FBTask *task = [[FBTaskBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"1"]]
    startSynchronously];

  NSError *error = nil;
  BOOL success = [task.exitCode awaitWithTimeout:FBControlCoreGlobalConfiguration.fastTimeout error:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
}

- (void)testAwaitingTerminationOfShortLivedProcess
{
  FBTask *task = [[FBTaskBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"0"]]
    startSynchronously];

  XCTAssertNotNil([task.exitCode awaitWithTimeout:1 error:nil]);
  XCTAssertEqual(task.statLoc.state, FBFutureStateDone);
  XCTAssertEqual(task.exitCode.state, FBFutureStateDone);
  XCTAssertEqual(task.signal.state, FBFutureStateFailed);
}

- (void)testCallsHandlerWithAsynchronousTermination
{
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"Termination Handler Called"];
  [[[FBTaskBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"1"]]
    runUntilCompletionWithAcceptableExitCodes:nil]
    onQueue:dispatch_get_main_queue() notifyOfCompletion:^(id _) {
      [expectation fulfill];
    }];

  [self waitForExpectations:@[expectation] timeout:FBControlCoreGlobalConfiguration.fastTimeout];
}

- (void)testAwaitingTerminationDoesNotTerminateStalledTask
{
  XCTestExpectation *expectation = [[XCTestExpectation alloc] initWithDescription:@"Termination Handler Called"];
  expectation.inverted = YES;
  FBTask *task = [[FBTaskBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"1000"]]
    startSynchronously];

  [task.statLoc onQueue:dispatch_get_main_queue() notifyOfCompletion:^(id _) {
    [expectation fulfill];
  }];

  NSError *error = nil;
  BOOL waitSuccess = [task.exitCode awaitWithTimeout:2 error:&error] != nil;
  XCTAssertFalse(waitSuccess);
  XCTAssertNotNil(error);
  XCTAssertFalse(task.statLoc.hasCompleted);
  XCTAssertFalse(task.exitCode.hasCompleted);
  XCTAssertFalse(task.signal.hasCompleted);

  [self waitForExpectations:@[expectation] timeout:2];
}

- (void)testInputReading
{
  NSData *expected = [@"FOO BAR BAZ" dataUsingEncoding:NSUTF8StringEncoding];

  FBTask *task = [[[[[FBTaskBuilder
    withLaunchPath:@"/bin/cat" arguments:@[]]
    withStdInConnected]
    withStdOutInMemoryAsData]
    withStdErrToDevNull]
    startSynchronously];

  XCTAssertTrue([task.stdIn conformsToProtocol:@protocol(FBDataConsumer)]);
  [task.stdIn consumeData:expected];
  [task.stdIn consumeEndOfFile];

  NSError *error = nil;
  BOOL waitSuccess = [task.exitCode awaitWithTimeout:2 error:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(waitSuccess);

  XCTAssertEqualObjects(expected, task.stdOut);
}

- (void)testInputStream
{
  NSString *expected = @"FOO BAR BAZ";

  FBProcessInput<NSOutputStream *> *input = FBProcessInput.inputFromStream;
  NSOutputStream *stream = input.contents;

  FBTask *task = [[[[[FBTaskBuilder
    withLaunchPath:@"/bin/cat" arguments:@[]]
    withStdIn:input]
    withStdOutInMemoryAsString]
    withStdErrToDevNull]
    startSynchronously];

  XCTAssertTrue([stream isKindOfClass:NSOutputStream.class]);
  XCTAssertTrue([task.stdIn isKindOfClass:NSOutputStream.class]);
  [stream open];
  [stream write:(const uint8_t *)expected.UTF8String maxLength:strlen(expected.UTF8String)];
  [stream close];

  NSError *error = nil;
  BOOL waitSuccess = [task.exitCode awaitWithTimeout:2 error:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(waitSuccess);

  XCTAssertEqualObjects(expected, task.stdOut);
}

- (void)testInputStreamWithBrokenPipe
{
  NSString *expected = @"FOO BAR BAZ";

  FBProcessInput<NSOutputStream *> *input = FBProcessInput.inputFromStream;
  NSOutputStream *stream = input.contents;

  FBTask *task = [[[[[FBTaskBuilder
    withLaunchPath:@"/bin/cat" arguments:@[]]
    withStdIn:input]
    withStdOutInMemoryAsString]
    withStdErrToDevNull]
    startSynchronously];

  XCTAssertTrue([stream isKindOfClass:NSOutputStream.class]);
  XCTAssertTrue([task.stdIn isKindOfClass:NSOutputStream.class]);
  [stream open];
  [stream write:(const uint8_t *)expected.UTF8String maxLength:strlen(expected.UTF8String)];
  [stream close];

  XCTAssertEqual([stream write:(const uint8_t *)expected.UTF8String maxLength:strlen(expected.UTF8String)], -1);
  XCTAssertNotNil(stream.streamError);

  NSError *error = nil;
  BOOL waitSuccess = [task.exitCode awaitWithTimeout:2 error:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(waitSuccess);

  XCTAssertEqualObjects(expected, task.stdOut);
}

- (void)testOutputStream
{
  NSString *expected = @"FOO BAR BAZ";

  FBTask *task = [[[[FBTaskBuilder
    withLaunchPath:@"/bin/echo" arguments:@[@"FOO BAR BAZ"]]
    withStdErrToDevNull]
    withStdOutToInputStream]
    startSynchronously];

  NSInputStream *stream = task.stdOut;
  XCTAssertTrue([stream isKindOfClass:NSInputStream.class]);
  [stream open];

  NSMutableData *output = NSMutableData.data;
  while (true) {
    uint8 buffer[8];
    NSInteger result = [stream read:buffer maxLength:8];
    if (result < 1) {
      break;
    }
    [output appendBytes:buffer length:(NSUInteger)result];
  }
  NSString *actual = [[[NSString alloc] initWithData:output encoding:NSASCIIStringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.newlineCharacterSet];
  XCTAssertEqualObjects(expected, actual);

  NSError *error = nil;
  BOOL waitSuccess = [task.exitCode awaitWithTimeout:2 error:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(waitSuccess);
}

- (void)testInputFromData
{
  NSData *expected = [@"FOO BAR BAZ" dataUsingEncoding:NSUTF8StringEncoding];

  FBTask *task = [[[[[FBTaskBuilder
    withLaunchPath:@"/bin/cat" arguments:@[]]
    withStdInFromData:expected]
    withStdOutInMemoryAsData]
    withStdErrToDevNull]
    startSynchronously];

  NSError *error = nil;
  BOOL waitSuccess = [task.exitCode awaitWithTimeout:2 error:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(waitSuccess);

  XCTAssertEqualObjects(expected, task.stdOut);
}

- (void)testSendingSIGINT
{
  FBTask *task = [[FBTaskBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"1000000"]]
    startSynchronously];

  XCTAssertEqual(task.statLoc.state, FBFutureStateRunning);
  XCTAssertEqual(task.exitCode.state, FBFutureStateRunning);
  XCTAssertEqual(task.signal.state, FBFutureStateRunning);

  NSError *error = nil;
  FBFuture *future = [task sendSignal:SIGINT];
  BOOL success = [future await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(task.exitCode.state, FBFutureStateFailed);
  XCTAssertEqual(task.signal.state, FBFutureStateDone);
  XCTAssertEqualObjects(task.signal.result, @(SIGINT));
}

- (void)testSendingSIGKILL
{
  FBTask *task = [[FBTaskBuilder
    withLaunchPath:@"/bin/sleep" arguments:@[@"1000000"]]
    startSynchronously];

  XCTAssertEqual(task.statLoc.state, FBFutureStateRunning);
  XCTAssertEqual(task.exitCode.state, FBFutureStateRunning);
  XCTAssertEqual(task.signal.state, FBFutureStateRunning);

  NSError *error = nil;
  BOOL success = [[task sendSignal:SIGKILL] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(task.statLoc.state, FBFutureStateDone);
  XCTAssertEqual(task.exitCode.state, FBFutureStateFailed);
  XCTAssertEqual(task.signal.state, FBFutureStateDone);
  XCTAssertEqualObjects(task.signal.result, @(SIGKILL));
}

- (void)testHUPBackoffToKILL
{
  FBTask *task = [[FBTaskBuilder
    withLaunchPath:@"/usr/bin/nohup" arguments:@[@"/bin/sleep", @"10000000"]]
    startSynchronously];

  XCTAssertEqual(task.statLoc.state, FBFutureStateRunning);
  XCTAssertEqual(task.exitCode.state, FBFutureStateRunning);
  XCTAssertEqual(task.signal.state, FBFutureStateRunning);

  NSError *error = nil;
  BOOL success = [[task sendSignal:SIGHUP backingOffToKillWithTimeout:0.5 logger:[FBControlCoreLoggerDouble new]] await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);
  XCTAssertEqual(task.statLoc.state, FBFutureStateDone);
  XCTAssertEqual(task.exitCode.state, FBFutureStateFailed);
  XCTAssertEqual(task.signal.state, FBFutureStateDone);
  XCTAssertEqual(task.signal.result, @(SIGKILL));

  success = [task.statLoc await:&error] != nil;
  XCTAssertEqual(task.statLoc.state, FBFutureStateDone);
  XCTAssertEqual(task.exitCode.state, FBFutureStateFailed);
  XCTAssertEqual(task.signal.state, FBFutureStateDone);
}

- (void)testPipingInputToSuccessivelyRunTasksSucceeds
{
  NSString *tarSource = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.tar.gz", NSUUID.UUID.UUIDString]];
  NSString *tarDestination = [tarSource stringByAppendingString:@".destination"];

  NSError *error = nil;
  BOOL success = [NSFileManager.defaultManager createDirectoryAtPath:tarDestination withIntermediateDirectories:YES attributes:nil error:&error];
  XCTAssertNil(error);
  XCTAssertTrue(success);

  success = [[[[[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/tar"]
    withArguments:@[@"-zcvf", tarSource, FBControlCoreFixtures.bundleResource]]
    withStdOutToDevNull]
    withStdErrToDevNull]
    runUntilCompletionWithAcceptableExitCodes:nil]
    mapReplace:NSNull.null]
    await:&error] != nil;
  XCTAssertNil(error);
  XCTAssertTrue(success);

  NSData *tarData = [NSData dataWithContentsOfFile:tarSource];

  for (NSUInteger count = 0; count < 10; count++) {
    success = [[[[[[[[FBTaskBuilder
      withLaunchPath:@"/usr/bin/tar"]
      withArguments:@[@"-C", tarDestination, @"-zxpf", @"-"]]
      withStdInFromData:tarData]
      withStdOutToDevNull]
      withStdErrToDevNull]
      runUntilCompletionWithAcceptableExitCodes:nil]
      mapReplace:NSNull.null]
      await:&error] != nil;
    XCTAssertNil(error);
    XCTAssertTrue(success);
  }
}

@end
