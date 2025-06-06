//
//  SVGAImageView.m
//  SVGAPlayer
//
//  Created by 崔明辉 on 2017/10/17.
//  Copyright © 2017年 UED Center. All rights reserved.
//

#import "SVGAImageView.h"
#import "SVGAParser.h"

static SVGAParser *sharedParser;

@implementation SVGAImageView

+ (void)load {
    sharedParser = [SVGAParser new];
}

- (void)setCustomCacheDir:(NSString *)customCacheDir {
    sharedParser.customCacheDir = customCacheDir;
}

- (NSString *)customCacheDir {
    return  sharedParser.customCacheDir;
}
+(SVGAParser *_Nullable)parser {
    return  sharedParser;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        _autoPlay = YES;
    }
    return self;
}

- (void)setImageName:(NSString *)imageName {
    _imageName = imageName;
    if ([imageName hasPrefix:@"http://"] || [imageName hasPrefix:@"https://"]) {
        [sharedParser parseWithURL:[NSURL URLWithString:imageName] completionBlock:^(SVGAVideoEntity * _Nullable videoItem) {
            [self setVideoItem:videoItem];
            if (self.autoPlay) {
                [self startAnimation];
            }
        } failureBlock:nil];
    }
    else {
        [sharedParser parseWithNamed:imageName inBundle:nil completionBlock:^(SVGAVideoEntity * _Nonnull videoItem) {
            [self setVideoItem:videoItem];
            if (self.autoPlay) {
                [self startAnimation];
            }
        } failureBlock:nil];
    }
}


+(void)cahceSvgaWithUrl:(NSString *)url success: (void (^ _Nonnull)(void))success fail: (void (^ _Nonnull)(void))fail {
    if ([url hasPrefix:@"http://"] || [url hasPrefix:@"https://"]) {
        [sharedParser parseWithURL:[NSURL URLWithString:url] completionBlock:^(SVGAVideoEntity * _Nullable videoItem) {
            success();
        } failureBlock: ^(NSError * err){
            fail();
        }];
    }
}
@end
