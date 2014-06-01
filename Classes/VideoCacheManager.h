//
//  VideoDirectoryManager.h
//  SmilePlayer2
//
//  Created by Pontago on 2014/01/12.
//
//

#import <Foundation/Foundation.h>
#include "libavformat/url.h"
#include "libavformat/avio.h"

@interface VideoCacheManager : NSObject <NSURLConnectionDelegate, NSURLConnectionDataDelegate>
- (BOOL)open:(NSString*)url;
- (void)close;
- (int)readVideo:(uint8_t*)buf size:(int)size;
- (int64_t)seekVideo:(int64_t)offset whence:(int)whence;
- (CGFloat)preloadProgressValue;

@property (nonatomic, readonly) AVIOContext *ioContext;
@property (nonatomic) BOOL stop;
@end
