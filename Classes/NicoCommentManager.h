//
//  NicoCommentManager.h
//  SmilePlayer2
//
//  Created by pontago on 2014/04/21.
//
//

#import <Foundation/Foundation.h>

extern CGFloat const COMMENT_DURATION;
extern CGFloat const COMMENT_TOP_OR_BOTTOM_DURATION;

@protocol NicoCommentManagerDelegate <NSObject>
- (CGFloat)willShowComments:(BOOL)seek;
@end

@interface NicoCommentManager : NSObject
@property (nonatomic, strong) NSArray *comments;
@property (nonatomic, weak) id<NicoCommentManagerDelegate> delegate;

- (id)initWithComments:(NSArray*)comments delegate:(id<NicoCommentManagerDelegate>)delegate;
+ (id)nicoCommentManagerWithComments:(NSArray*)comments delegate:(id<NicoCommentManagerDelegate>)delegate;

- (void)setupPresentView:(UIView*)view videoSize:(CGSize)videoSize screenSize:(CGSize)screenSize isLandscape:(BOOL)isLandscape;
- (void)start;
- (void)stop;

- (void)deleteAllCommentLayer;
- (void)startCommentLayer;
- (void)stopCommentLayer;
- (void)seekCommentLayer:(BOOL)pause;
@end
