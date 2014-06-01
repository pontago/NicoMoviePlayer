//
//  NicoCommentUtil.h
//  SmilePlayer2
//
//  Created by pontago on 2014/04/05.
//
//

#import <Foundation/Foundation.h>

#import "CommentTextLayer.h"

@interface NicoCommentUtil : NSObject
- (NSInteger)commentPosition:(NSString*)mail;
- (NSInteger)commentSize:(NSString*)mail;
- (NSNumber*)commentColor:(NSString*)mail;
@end
