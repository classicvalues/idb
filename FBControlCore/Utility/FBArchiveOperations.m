/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBArchiveOperations.h"

#import "FBControlCoreError.h"
#import "FBControlCoreLogger.h"
#import "FBTask.h"
#import "FBTaskBuilder.h"

FBCompressionFormat const FBCompressionFormatGZIP = @"gzip";
FBCompressionFormat const FBCompressionFormatZSTD = @"zstd";

static NSString *const BSDTarPath = @"/usr/bin/bsdtar";

@implementation FBArchiveOperations

+ (FBFuture<NSString *> *)extractArchiveAtPath:(NSString *)path toPath:(NSString *)extractPath queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  return [[[[[[[FBTaskBuilder
    withLaunchPath:BSDTarPath]
    withArguments:@[@"-zxp", @"-C", extractPath, @"-f", path]]
    withStdErrToLoggerAndErrorMessage:logger.debug]
    withStdOutToLogger:logger.debug]
    withTaskLifecycleLoggingTo:logger]
    runUntilCompletionWithAcceptableExitCodes:[NSSet setWithObject:@0]]
    mapReplace:extractPath];
}

+ (FBFuture<NSString *> *)extractArchiveFromStream:(FBProcessInput *)stream toPath:(NSString *)extractPath queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger compression:(FBCompressionFormat)compression
{
  NSArray *extractCommand = @[@"-zxp", @"-C", extractPath, @"-f", @"-"];
  if (compression == FBCompressionFormatZSTD) {
    extractCommand = @[@"--use-compress-program", @"pzstd -d", @"-xp", @"-C", extractPath, @"-f", @"-"];
  }
  
  return [[[[[[[[FBTaskBuilder
    withLaunchPath:BSDTarPath]
    withArguments:extractCommand]
    withStdIn:stream]
    withStdErrToLoggerAndErrorMessage:logger.debug]
    withStdOutToLogger:logger.debug]
    withTaskLifecycleLoggingTo:logger]
    runUntilCompletionWithAcceptableExitCodes:[NSSet setWithObject:@0]]
    mapReplace:extractPath];
}

+ (FBFuture<NSString *> *)extractGzipFromStream:(FBProcessInput *)stream toPath:(NSString *)extractPath queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  return [[[[[[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/gunzip"]
    withArguments:@[@"--to-stdout"]]
    withStdIn:stream]
    withStdErrToLoggerAndErrorMessage:logger.debug]
    withStdOutPath:extractPath]
    withTaskLifecycleLoggingTo:logger]
    runUntilCompletionWithAcceptableExitCodes:[NSSet setWithObject:@0]]
    mapReplace:extractPath];
}

+ (FBFuture<FBTask<NSNull *, NSInputStream *, id> *> *)createGzipForPath:(NSString *)path queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  return (FBFuture<FBTask<NSNull *, NSInputStream *, id> *> *) [[[[[[FBTaskBuilder
    withLaunchPath:@"/usr/bin/gzip"]
    withArguments:@[@"--to-stdout", path]]
    withStdErrToLoggerAndErrorMessage:logger]
    withStdOutToInputStream]
    withTaskLifecycleLoggingTo:logger]
    start];
}

+ (FBFuture<FBTask<NSNull *, NSInputStream *, id> *> *)createGzippedTarForPath:(NSString *)path queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  NSError *error = nil;
  FBTaskBuilder<NSNull *, NSData *, id> *builder = [self createGzippedTarTaskBuilderForPath:path queue:queue logger:logger error:&error];
  if (!builder) {
    return [FBFuture futureWithError:error];
  }
  return [[builder
    withStdOutToInputStream]
    start];
}

+ (FBFuture<NSData *> *)createGzippedTarDataForPath:(NSString *)path queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger
{
  NSError *error = nil;
  FBTaskBuilder<NSNull *, NSData *, id> *builder = [self createGzippedTarTaskBuilderForPath:path queue:queue logger:logger error:&error];
  if (!builder) {
    return [FBFuture futureWithError:error];
  }
  return [[builder
    runUntilCompletionWithAcceptableExitCodes:[NSSet setWithObject:@0]]
    onQueue:queue map:^(FBTask<NSNull *, NSData *, id<FBControlCoreLogger>> *result) {
      return [result stdOut];
    }];
}

#pragma mark Private

+ (FBTaskBuilder<NSNull *, NSData *, id> *)createGzippedTarTaskBuilderForPath:(NSString *)path queue:(dispatch_queue_t)queue logger:(id<FBControlCoreLogger>)logger error:(NSError **)error
{
  BOOL isDirectory;
  if (![NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDirectory]) {
    return [[FBControlCoreError
      describeFormat:@"Path for tarring %@ doesn't exist", path]
      fail:error];
  }

  NSString *directory;
  NSString *fileName;
  if (isDirectory) {
    directory = path;
    fileName = @".";
    [logger.info logFormat:@"%@ is a directory, tarring with it as the root.", directory];
    if ([[NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:nil] count] < 1) {
      [logger.info logFormat:@"Attempting to tar directory at path %@, but it has no contents", path];
    }
  } else {
    directory = path.stringByDeletingLastPathComponent;
    fileName = path.lastPathComponent;
    [logger.info logFormat:@"%@ is a file, tarring relative to it's parent %@", path, directory];
    NSDictionary<NSString *, id> *fileAttributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    NSUInteger fileSize = [fileAttributes[NSFileSize] unsignedIntegerValue];
    if (fileSize <= 0) {
      [logger.info logFormat:@"Attempting to tar file at path %@, but it has no content", path];
    }
  }

  return (FBTaskBuilder<NSNull *, NSData *, id> *) [[[[[FBTaskBuilder
    withLaunchPath:BSDTarPath]
    withArguments:@[@"-zvc", @"-f", @"-", @"-C", directory, fileName]]
    withStdOutInMemoryAsData]
    withStdErrToLoggerAndErrorMessage:logger]
    withTaskLifecycleLoggingTo:logger];
}

@end
