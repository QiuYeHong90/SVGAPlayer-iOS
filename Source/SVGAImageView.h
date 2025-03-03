//
//  SVGAImageView.h
//  SVGAPlayer
//
//  Created by 崔明辉 on 2017/10/17.
//  Copyright © 2017年 UED Center. All rights reserved.
//

#import "SVGAPlayer.h"
@class SVGAParser;
@interface SVGAImageView : SVGAPlayer


@property (nonatomic, assign) IBInspectable BOOL autoPlay;
@property (nonatomic, strong) IBInspectable NSString *imageName;
/// 默认为空 lib/cache
@property (nonatomic, copy) NSString * _Nullable customCacheDir;
+(void)cahceSvgaWithUrl:(NSString *)url success: (void (^ _Nonnull)(void))success fail: (void (^ _Nonnull)(void))fail;

+(SVGAParser *_Nullable)parser;
@end
