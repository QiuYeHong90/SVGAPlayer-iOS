//
//  SVGAParser.m
//  SVGAPlayer
//
//  Created by 崔明辉 on 16/6/17.
//  Copyright © 2016年 UED Center. All rights reserved.
//

#import "SVGAParser.h"
#import "SVGAVideoEntity.h"
#import "Svga.pbobjc.h"
#import <zlib.h>
#import <SSZipArchive/SSZipArchive.h>
#import <CommonCrypto/CommonDigest.h>

#define ZIP_MAGIC_NUMBER "PK"

@interface SVGAParser ()

@end

@implementation SVGAParser

static NSOperationQueue *parseQueue;
static NSOperationQueue *unzipQueue;

+ (void)load {
    parseQueue = [NSOperationQueue new];
    parseQueue.maxConcurrentOperationCount = 8;
    unzipQueue = [NSOperationQueue new];
    unzipQueue.maxConcurrentOperationCount = 1;
}

- (void)parseWithURL:(nonnull NSURL *)URL
     completionBlock:(void ( ^ _Nonnull )(SVGAVideoEntity * _Nullable videoItem))completionBlock
        failureBlock:(void ( ^ _Nullable)(NSError * _Nullable error))failureBlock {
    [self parseWithURLRequest:[NSURLRequest requestWithURL:URL cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:20.0]
    completionBlock:completionBlock
       failureBlock:failureBlock];
}

- (void)parseWithURLRequest:(NSURLRequest *)URLRequest completionBlock:(void (^)(SVGAVideoEntity * _Nullable))completionBlock failureBlock:(void (^)(NSError * _Nullable))failureBlock {
    if (URLRequest.URL == nil) {
        if (failureBlock) {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                failureBlock([NSError errorWithDomain:@"SVGAParser" code:411 userInfo:@{NSLocalizedDescriptionKey: @"URL cannot be nil."}]);
            }];
        }
        return;
    }
    if ([[NSFileManager defaultManager] fileExistsAtPath:[self cacheDirectory:[self cacheKey:URLRequest.URL]]]) {
        
        [self parseWithCacheKey:[self cacheKey:URLRequest.URL] completionBlock:^(SVGAVideoEntity * _Nonnull videoItem) {
            if (completionBlock) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    completionBlock(videoItem);
                }];
            }
        } failureBlock:^(NSError * _Nonnull error) {
            [self clearCache:[self cacheKey:URLRequest.URL]];
            if (failureBlock) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    failureBlock(error);
                }];
            }
        }];
        return;
    }
    [[[NSURLSession sharedSession] dataTaskWithRequest:URLRequest completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error == nil && data != nil) {
            [self parseWithData:data cacheKey:[self cacheKey:URLRequest.URL] 
                      isNetWork: YES
                completionBlock:^(SVGAVideoEntity * _Nonnull videoItem) {
                if (completionBlock) {
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        completionBlock(videoItem);
                    }];
                }
            } failureBlock:^(NSError * _Nonnull error) {
                [self clearCache:[self cacheKey:URLRequest.URL]];
                if (failureBlock) {
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        failureBlock(error);
                    }];
                }
            }];
        }
        else {
            if (failureBlock) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    failureBlock(error);
                }];
            }
        }
    }] resume];
}

- (void)parseWithNamed:(NSString *)named
              inBundle:(NSBundle *)inBundle
       completionBlock:(void (^)(SVGAVideoEntity * _Nonnull))completionBlock
          failureBlock:(void (^)(NSError * _Nonnull))failureBlock {
    NSString *filePath = [(inBundle ?: [NSBundle mainBundle]) pathForResource:named ofType:@"svga"];
    if (filePath == nil) {
        if (failureBlock) {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                failureBlock([NSError errorWithDomain:@"SVGAParser" code:404 userInfo:@{NSLocalizedDescriptionKey: @"File not exist."}]);
            }];
        }
        return;
    }
    [self parseWithData:[NSData dataWithContentsOfFile:filePath]
               cacheKey:[self cacheKey:[NSURL fileURLWithPath:filePath]]
              isNetWork: NO
        completionBlock:completionBlock
           failureBlock:failureBlock];
}

- (void)parseWithCacheKey:(nonnull NSString *)cacheKey
          completionBlock:(void ( ^ _Nullable)(SVGAVideoEntity * _Nonnull videoItem))completionBlock
             failureBlock:(void ( ^ _Nullable)(NSError * _Nonnull error))failureBlock {
    [parseQueue addOperationWithBlock:^{
        SVGAVideoEntity *cacheItem = [SVGAVideoEntity readCache:cacheKey];
        if (cacheItem != nil) {
            if (completionBlock) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    completionBlock(cacheItem);
                }];
            }
            return;
        }
        NSString *cacheDir = [self cacheDirectory:cacheKey];
        NSLog(@"SVGA === cache %@",cacheDir);
        if ([[NSFileManager defaultManager] fileExistsAtPath:[cacheDir stringByAppendingString:@"/movie.binary"]]) {
            NSError *err;
            NSData *protoData = [NSData dataWithContentsOfFile:[cacheDir stringByAppendingString:@"/movie.binary"]];
            SVGAProtoMovieEntity *protoObject = [SVGAProtoMovieEntity parseFromData:protoData error:&err];
            if (!err && [protoObject isKindOfClass:[SVGAProtoMovieEntity class]]) {
                SVGAVideoEntity *videoItem = [[SVGAVideoEntity alloc] initWithProtoObject:protoObject cacheDir:cacheDir];
                [videoItem resetImagesWithProtoObject:protoObject];
                [videoItem resetSpritesWithProtoObject:protoObject];
                [videoItem resetAudiosWithProtoObject:protoObject];
                if (self.enabledMemoryCache) {
                    [videoItem saveCache:cacheKey];
                } else {
                    [videoItem saveWeakCache:cacheKey];
                }
                if (completionBlock) {
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        completionBlock(videoItem);
                    }];
                }
            }
            else {
                if (failureBlock) {
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        failureBlock([NSError errorWithDomain:NSFilePathErrorKey code:-1 userInfo:nil]);
                    }];
                }
            }
        } else if ([[NSFileManager defaultManager] fileExistsAtPath:[cacheDir stringByAppendingString:@"/index200.svga"]]) {
            NSData *data = [NSData dataWithContentsOfFile:[cacheDir stringByAppendingString:@"/index200.svga"]];
            NSLog(@"path ===1 %@",cacheDir);
            NSData *inflateData = [self zlibInflate:data];
            NSError *err;
            SVGAProtoMovieEntity *protoObject = [SVGAProtoMovieEntity parseFromData:inflateData error:&err];
            if (!err && [protoObject isKindOfClass:[SVGAProtoMovieEntity class]]) {
                SVGAVideoEntity *videoItem = [[SVGAVideoEntity alloc] initWithProtoObject:protoObject cacheDir:@""];
                [videoItem resetImagesWithProtoObject:protoObject];
                [videoItem resetSpritesWithProtoObject:protoObject];
                [videoItem resetAudiosWithProtoObject:protoObject];
                if (self.enabledMemoryCache) {
                    [videoItem saveCache:cacheKey];
                } else {
                    [videoItem saveWeakCache:cacheKey];
                }
                if (completionBlock) {
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        completionBlock(videoItem);
                    }];
                }
            } else {
                if (failureBlock) {
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        failureBlock([NSError errorWithDomain:NSFilePathErrorKey code:-1 userInfo:nil]);
                    }];
                }
            }
            
        }
        else {
            NSError *err;
            NSData *JSONData = [NSData dataWithContentsOfFile:[cacheDir stringByAppendingString:@"/movie.spec"]];
            if (JSONData != nil) {
                NSDictionary *JSONObject = [NSJSONSerialization JSONObjectWithData:JSONData options:kNilOptions error:&err];
                if ([JSONObject isKindOfClass:[NSDictionary class]]) {
                    SVGAVideoEntity *videoItem = [[SVGAVideoEntity alloc] initWithJSONObject:JSONObject cacheDir:cacheDir];
                    [videoItem resetImagesWithJSONObject:JSONObject];
                    [videoItem resetSpritesWithJSONObject:JSONObject];
                    if (self.enabledMemoryCache) {
                        [videoItem saveCache:cacheKey];
                    } else {
                        [videoItem saveWeakCache:cacheKey];
                    }
                    if (completionBlock) {
                        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                            completionBlock(videoItem);
                        }];
                    }
                }
            }
            else {
                if (failureBlock) {
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        failureBlock([NSError errorWithDomain:NSFilePathErrorKey code:-1 userInfo:nil]);
                    }];
                }
            }
        }
    }];
}

- (void)clearCache:(nonnull NSString *)cacheKey {
    NSString *cacheDir = [self cacheDirectory:cacheKey];
    [[NSFileManager defaultManager] removeItemAtPath:cacheDir error:NULL];
}


-(BOOL)isCacheWithUrl: (NSString *_Nonnull)urlStr {
    NSURL * url = [[NSURL alloc] initWithString:urlStr];
    if (url) {
        return [[NSFileManager defaultManager] fileExistsAtPath:[self cacheDirectory:[self cacheKey:url]]];
    }
    return NO;
}

-(NSString *_Nullable)cachePathWithUrl: (NSString *_Nonnull)urlStr {
    NSURL * url = [[NSURL alloc] initWithString:urlStr];
    if (url) {
        return [self cacheDirectory:[self cacheKey:url]];
    }
    return nil;
}

+ (BOOL)isZIPData:(NSData *)data {
    BOOL result = NO;
    if (!strncmp([data bytes], ZIP_MAGIC_NUMBER, strlen(ZIP_MAGIC_NUMBER))) {
        result = YES;
    }
    return result;
}

- (void)parseWithData:(nonnull NSData *)data
             cacheKey:(nonnull NSString *)cacheKey
            isNetWork: (BOOL)isNetWork
      completionBlock:(void ( ^ _Nullable)(SVGAVideoEntity * _Nonnull videoItem))completionBlock
         failureBlock:(void ( ^ _Nullable)(NSError * _Nonnull error))failureBlock {
    SVGAVideoEntity *cacheItem = [SVGAVideoEntity readCache:cacheKey];
    if (cacheItem != nil) {
        if (completionBlock) {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                completionBlock(cacheItem);
            }];
        }
        return;
    }
    if (!data || data.length < 4) {
        return;
    }
    if (![SVGAParser isZIPData:data]) {
        NSLog(@"SVGA === 2.0.0");
        // Maybe is SVGA 2.0.0
        [parseQueue addOperationWithBlock:^{
            NSData *inflateData = [self zlibInflate:data];
            if (![[NSFileManager defaultManager] fileExistsAtPath:[self cacheDirectory:cacheKey]] && isNetWork) {
                if (data != nil) {
                    
                    NSString *cacheDir = [self cacheDirectory:cacheKey];
                    if ([cacheDir isKindOfClass:[NSString class]]) {
                        [[NSFileManager defaultManager] createDirectoryAtPath:cacheDir withIntermediateDirectories:NO attributes:nil error:nil];
                        
                        NSString * path = [cacheDir stringByAppendingString:@"/index200.svga"];
                        NSLog(@"path === %@",path);
                        [data writeToFile:path atomically:YES];
                    }
                }
                
                
            }
            
            NSError *err;
            SVGAProtoMovieEntity *protoObject = [SVGAProtoMovieEntity parseFromData:inflateData error:&err];
            if (!err && [protoObject isKindOfClass:[SVGAProtoMovieEntity class]]) {
                SVGAVideoEntity *videoItem = [[SVGAVideoEntity alloc] initWithProtoObject:protoObject cacheDir:@""];
                [videoItem resetImagesWithProtoObject:protoObject];
                [videoItem resetSpritesWithProtoObject:protoObject];
                [videoItem resetAudiosWithProtoObject:protoObject];
                if (self.enabledMemoryCache) {
                    [videoItem saveCache:cacheKey];
                } else {
                    [videoItem saveWeakCache:cacheKey];
                }
                if (completionBlock) {
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        completionBlock(videoItem);
                    }];
                }
            }
        }];
        return ;
    }
    // 遮罩 层svga
    NSLog(@"SVGA === matte layer ");
    [unzipQueue addOperationWithBlock:^{
        if ([[NSFileManager defaultManager] fileExistsAtPath:[self cacheDirectory:cacheKey]]) {
            [self parseWithCacheKey:cacheKey completionBlock:^(SVGAVideoEntity * _Nonnull videoItem) {
                if (completionBlock) {
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        completionBlock(videoItem);
                    }];
                }
            } failureBlock:^(NSError * _Nonnull error) {
                [self clearCache:cacheKey];
                if (failureBlock) {
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        failureBlock(error);
                    }];
                }
            }];
            return;
        }
        NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingFormat:@"%u.svga", arc4random()];
        if (data != nil) {
            [data writeToFile:tmpPath atomically:YES];
            NSString *cacheDir = [self cacheDirectory:cacheKey];
            NSLog(@"SVGA === matte layer %@",cacheDir);
            if ([cacheDir isKindOfClass:[NSString class]]) {
                [[NSFileManager defaultManager] createDirectoryAtPath:cacheDir withIntermediateDirectories:NO attributes:nil error:nil];
                [SSZipArchive unzipFileAtPath:tmpPath toDestination:[self cacheDirectory:cacheKey] progressHandler:^(NSString * _Nonnull entry, unz_file_info zipInfo, long entryNumber, long total) {
                    
                } completionHandler:^(NSString *path, BOOL succeeded, NSError *error) {
                    if (error != nil) {
                        if (failureBlock) {
                            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                                failureBlock(error);
                            }];
                        }
                    }
                    else {
                        if ([[NSFileManager defaultManager] fileExistsAtPath:[cacheDir stringByAppendingString:@"/movie.binary"]]) {
                            NSError *err;
                            NSData *protoData = [NSData dataWithContentsOfFile:[cacheDir stringByAppendingString:@"/movie.binary"]];
                            SVGAProtoMovieEntity *protoObject = [SVGAProtoMovieEntity parseFromData:protoData error:&err];
                            if (!err) {
                                SVGAVideoEntity *videoItem = [[SVGAVideoEntity alloc] initWithProtoObject:protoObject cacheDir:cacheDir];
                                [videoItem resetImagesWithProtoObject:protoObject];
                                [videoItem resetSpritesWithProtoObject:protoObject];
                                if (self.enabledMemoryCache) {
                                    [videoItem saveCache:cacheKey];
                                } else {
                                    [videoItem saveWeakCache:cacheKey];
                                }
                                if (completionBlock) {
                                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                                        completionBlock(videoItem);
                                    }];
                                }
                            }
                            else {
                                if (failureBlock) {
                                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                                        failureBlock([NSError errorWithDomain:NSFilePathErrorKey code:-1 userInfo:nil]);
                                    }];
                                }
                            }
                        }
                        else if ([[NSFileManager defaultManager] fileExistsAtPath:[cacheDir stringByAppendingString:@"/index200.svga"]]) {
                            NSData *data = [NSData dataWithContentsOfFile:[cacheDir stringByAppendingString:@"/index200.svga"]];
                            NSLog(@"path ===1 %@",cacheDir);
                            NSData *inflateData = [self zlibInflate:data];
                            NSError *err;
                            SVGAProtoMovieEntity *protoObject = [SVGAProtoMovieEntity parseFromData:inflateData error:&err];
                            if (!err && [protoObject isKindOfClass:[SVGAProtoMovieEntity class]]) {
                                SVGAVideoEntity *videoItem = [[SVGAVideoEntity alloc] initWithProtoObject:protoObject cacheDir:@""];
                                [videoItem resetImagesWithProtoObject:protoObject];
                                [videoItem resetSpritesWithProtoObject:protoObject];
                                [videoItem resetAudiosWithProtoObject:protoObject];
                                if (self.enabledMemoryCache) {
                                    [videoItem saveCache:cacheKey];
                                } else {
                                    [videoItem saveWeakCache:cacheKey];
                                }
                                if (completionBlock) {
                                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                                        completionBlock(videoItem);
                                    }];
                                }
                            } else {
                                if (failureBlock) {
                                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                                        failureBlock([NSError errorWithDomain:NSFilePathErrorKey code:-1 userInfo:nil]);
                                    }];
                                }
                            }
                            
                        }
                        else {
                            NSError *err;
                            NSData *JSONData = [NSData dataWithContentsOfFile:[cacheDir stringByAppendingString:@"/movie.spec"]];
                            if (JSONData != nil) {
                                NSDictionary *JSONObject = [NSJSONSerialization JSONObjectWithData:JSONData options:kNilOptions error:&err];
                                if ([JSONObject isKindOfClass:[NSDictionary class]]) {
                                    SVGAVideoEntity *videoItem = [[SVGAVideoEntity alloc] initWithJSONObject:JSONObject cacheDir:cacheDir];
                                    [videoItem resetImagesWithJSONObject:JSONObject];
                                    [videoItem resetSpritesWithJSONObject:JSONObject];
                                    if (self.enabledMemoryCache) {
                                        [videoItem saveCache:cacheKey];
                                    } else {
                                        [videoItem saveWeakCache:cacheKey];
                                    }
                                    if (completionBlock) {
                                        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                                            completionBlock(videoItem);
                                        }];
                                    }
                                }
                            }
                            else {
                                if (failureBlock) {
                                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                                        failureBlock([NSError errorWithDomain:NSFilePathErrorKey code:-1 userInfo:nil]);
                                    }];
                                }
                            }
                        }
                    }
                }];
            }
            else {
                if (failureBlock) {
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        failureBlock([NSError errorWithDomain:NSFilePathErrorKey code:-1 userInfo:nil]);
                    }];
                }
            }
        }
        else {
            if (failureBlock) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    failureBlock([NSError errorWithDomain:@"Data Error" code:-1 userInfo:nil]);
                }];
            }
        }
    }];
}

- (void)parseWithData:(nonnull NSData *)data
             cacheKey:(nonnull NSString *)cacheKey
      completionBlock:(void ( ^ _Nullable)(SVGAVideoEntity * _Nonnull videoItem))completionBlock
         failureBlock:(void ( ^ _Nullable)(NSError * _Nonnull error))failureBlock {
    SVGAVideoEntity *cacheItem = [SVGAVideoEntity readCache:cacheKey];
    if (cacheItem != nil) {
        if (completionBlock) {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                completionBlock(cacheItem);
            }];
        }
        return;
    }
    if (!data || data.length < 4) {
        return;
    }
    if (![SVGAParser isZIPData:data]) {
        // Maybe is SVGA 2.0.0
        [parseQueue addOperationWithBlock:^{
            NSData *inflateData = [self zlibInflate:data];
            NSError *err;
            SVGAProtoMovieEntity *protoObject = [SVGAProtoMovieEntity parseFromData:inflateData error:&err];
            if (!err && [protoObject isKindOfClass:[SVGAProtoMovieEntity class]]) {
                SVGAVideoEntity *videoItem = [[SVGAVideoEntity alloc] initWithProtoObject:protoObject cacheDir:@""];
                [videoItem resetImagesWithProtoObject:protoObject];
                [videoItem resetSpritesWithProtoObject:protoObject];
                [videoItem resetAudiosWithProtoObject:protoObject];
                if (self.enabledMemoryCache) {
                    [videoItem saveCache:cacheKey];
                } else {
                    [videoItem saveWeakCache:cacheKey];
                }
                if (completionBlock) {
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        completionBlock(videoItem);
                    }];
                }
            }
        }];
        return ;
    }
    [unzipQueue addOperationWithBlock:^{
        if ([[NSFileManager defaultManager] fileExistsAtPath:[self cacheDirectory:cacheKey]]) {
            [self parseWithCacheKey:cacheKey completionBlock:^(SVGAVideoEntity * _Nonnull videoItem) {
                if (completionBlock) {
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        completionBlock(videoItem);
                    }];
                }
            } failureBlock:^(NSError * _Nonnull error) {
                [self clearCache:cacheKey];
                if (failureBlock) {
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        failureBlock(error);
                    }];
                }
            }];
            return;
        }
        NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingFormat:@"%u.svga", arc4random()];
        if (data != nil) {
            [data writeToFile:tmpPath atomically:YES];
            NSString *cacheDir = [self cacheDirectory:cacheKey];
            if ([cacheDir isKindOfClass:[NSString class]]) {
                [[NSFileManager defaultManager] createDirectoryAtPath:cacheDir withIntermediateDirectories:NO attributes:nil error:nil];
                [SSZipArchive unzipFileAtPath:tmpPath toDestination:[self cacheDirectory:cacheKey] progressHandler:^(NSString * _Nonnull entry, unz_file_info zipInfo, long entryNumber, long total) {
                    
                } completionHandler:^(NSString *path, BOOL succeeded, NSError *error) {
                    if (error != nil) {
                        if (failureBlock) {
                            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                                failureBlock(error);
                            }];
                        }
                    }
                    else {
                        if ([[NSFileManager defaultManager] fileExistsAtPath:[cacheDir stringByAppendingString:@"/movie.binary"]]) {
                            NSError *err;
                            NSData *protoData = [NSData dataWithContentsOfFile:[cacheDir stringByAppendingString:@"/movie.binary"]];
                            SVGAProtoMovieEntity *protoObject = [SVGAProtoMovieEntity parseFromData:protoData error:&err];
                            if (!err) {
                                SVGAVideoEntity *videoItem = [[SVGAVideoEntity alloc] initWithProtoObject:protoObject cacheDir:cacheDir];
                                [videoItem resetImagesWithProtoObject:protoObject];
                                [videoItem resetSpritesWithProtoObject:protoObject];
                                if (self.enabledMemoryCache) {
                                    [videoItem saveCache:cacheKey];
                                } else {
                                    [videoItem saveWeakCache:cacheKey];
                                }
                                if (completionBlock) {
                                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                                        completionBlock(videoItem);
                                    }];
                                }
                            }
                            else {
                                if (failureBlock) {
                                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                                        failureBlock([NSError errorWithDomain:NSFilePathErrorKey code:-1 userInfo:nil]);
                                    }];
                                }
                            }
                        }
                        else {
                            NSError *err;
                            NSData *JSONData = [NSData dataWithContentsOfFile:[cacheDir stringByAppendingString:@"/movie.spec"]];
                            if (JSONData != nil) {
                                NSDictionary *JSONObject = [NSJSONSerialization JSONObjectWithData:JSONData options:kNilOptions error:&err];
                                if ([JSONObject isKindOfClass:[NSDictionary class]]) {
                                    SVGAVideoEntity *videoItem = [[SVGAVideoEntity alloc] initWithJSONObject:JSONObject cacheDir:cacheDir];
                                    [videoItem resetImagesWithJSONObject:JSONObject];
                                    [videoItem resetSpritesWithJSONObject:JSONObject];
                                    if (self.enabledMemoryCache) {
                                        [videoItem saveCache:cacheKey];
                                    } else {
                                        [videoItem saveWeakCache:cacheKey];
                                    }
                                    if (completionBlock) {
                                        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                                            completionBlock(videoItem);
                                        }];
                                    }
                                }
                            }
                            else {
                                if (failureBlock) {
                                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                                        failureBlock([NSError errorWithDomain:NSFilePathErrorKey code:-1 userInfo:nil]);
                                    }];
                                }
                            }
                        }
                    }
                }];
            }
            else {
                if (failureBlock) {
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        failureBlock([NSError errorWithDomain:NSFilePathErrorKey code:-1 userInfo:nil]);
                    }];
                }
            }
        }
        else {
            if (failureBlock) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    failureBlock([NSError errorWithDomain:@"Data Error" code:-1 userInfo:nil]);
                }];
            }
        }
    }];
}

- (nonnull NSString *)cacheKey:(NSURL *)URL {
    return [self MD5String:URL.absoluteString];
}
- (void)clearCacheWithUrl:(NSURL *)URL {
    [self clearCache:[self cacheKey:URL]];
}



- (nullable NSString *)cacheDirectory:(NSString *)cacheKey {
    if (self.customCacheDir) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:self.customCacheDir]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:self.customCacheDir withIntermediateDirectories:YES attributes:nil error:nil];
        }
        return [self.customCacheDir stringByAppendingFormat:@"/%@", cacheKey];;
    }
    
    NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    cacheDir = [cacheDir stringByAppendingString:@"/SVGACache"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:cacheDir]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:cacheDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    self.customCacheDir = cacheDir;
    return [cacheDir stringByAppendingFormat:@"/%@", cacheKey];
}

- (NSString *)MD5String:(NSString *)str {
    const char *cstr = [str UTF8String];
    unsigned char result[16];
    CC_MD5(cstr, (CC_LONG)strlen(cstr), result);
    return [NSString stringWithFormat:
            @"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X",
            result[0], result[1], result[2], result[3],
            result[4], result[5], result[6], result[7],
            result[8], result[9], result[10], result[11],
            result[12], result[13], result[14], result[15]
            ];
}

- (NSData *)zlibInflate:(NSData *)data
{
    if ([data length] == 0) return data;
    
    unsigned full_length = (unsigned)[data length];
    unsigned half_length = (unsigned)[data length] / 2;
    
    NSMutableData *decompressed = [NSMutableData dataWithLength: full_length + half_length];
    BOOL done = NO;
    int status;
    
    z_stream strm;
    strm.next_in = (Bytef *)[data bytes];
    strm.avail_in = (unsigned)[data length];
    strm.total_out = 0;
    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;
    
    if (inflateInit (&strm) != Z_OK) return nil;
    
    while (!done)
    {
        // Make sure we have enough room and reset the lengths.
        if (strm.total_out >= [decompressed length])
            [decompressed increaseLengthBy: half_length];
        strm.next_out = [decompressed mutableBytes] + strm.total_out;
        strm.avail_out = (uInt)([decompressed length] - strm.total_out);
        
        // Inflate another chunk.
        status = inflate (&strm, Z_SYNC_FLUSH);
        if (status == Z_STREAM_END) done = YES;
        else if (status != Z_OK) break;
    }
    if (inflateEnd (&strm) != Z_OK) return nil;
    
    // Set real length.
    if (done)
    {
        [decompressed setLength: strm.total_out];
        return [NSData dataWithData: decompressed];
    }
    else return nil;
}

@end
