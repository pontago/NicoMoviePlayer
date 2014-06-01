//
//  videoSeekSlider.m
//  SmilePlayer2
//
//  Created by Pontago on 2014/01/15.
//
//

#import "VideoSeekSlider.h"

@interface VideoSeekSlider () {
    UIProgressView *_progressView;
}
- (UIImage*)_createImage:(CGSize)size withColor:(UIColor*)color;
@end

@implementation VideoSeekSlider

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
      UIImage *minTrackImage = [self _createImage:CGSizeMake(2.f, 20.f) 
                                        withColor:[UIColor colorWithRed:0.0 green:122.0/255.0 blue:1.0 alpha:1.0]];
      UIImage *thumbImage = [self _createImage:CGSizeMake(8.f, 17.f) 
                                     withColor:[UIColor colorWithRed:0.0 green:122.0/255.0 blue:1.0 alpha:1.0]];

      [self setMinimumTrackImage:minTrackImage forState:UIControlStateNormal];
      [self setMaximumTrackImage:[UIImage imageNamed:@"transparentBar"] forState:UIControlStateNormal];
      [self setThumbImage:thumbImage forState:UIControlStateNormal];
    }
    return self;
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect
{
    // Drawing code
}
*/

- (void)didMoveToSuperview {
    CGRect trackRect = [self trackRectForBounds:self.bounds];
    trackRect.origin.x += self.frame.origin.x;
    trackRect.origin.y += self.frame.origin.y;

    _progressView = [[UIProgressView alloc] initWithFrame:trackRect];
    _progressView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _progressView.progressTintColor = [UIColor grayColor];
    [self.superview insertSubview:_progressView belowSubview:self];
}

- (CGRect)trackRectForBounds:(CGRect)bounds {
    CGRect rect = bounds;
    rect.size.height = 2.f;
    return rect;
}

- (void)setPreloadValue:(float)value animated:(BOOL)animated {
    [_progressView setProgress:value animated:YES];
}


- (UIImage*)_createImage:(CGSize)size withColor:(UIColor*)color {
    CGRect fillRect = CGRectMake(0.f, 0.f, size.width, size.height);

    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();

    CGContextSetFillColorWithColor(context, color.CGColor);
    CGContextFillRect(context, fillRect);

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return image;
}
@end
