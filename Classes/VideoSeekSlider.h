//
//  videoSeekSlider.h
//  SmilePlayer2
//
//  Created by Pontago on 2014/01/15.
//
//

#import <UIKit/UIKit.h>
#import "CPSlider.h"

@interface VideoSeekSlider : CPSlider
- (void)setPreloadValue:(float)value animated:(BOOL)animated;
@end
