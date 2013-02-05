//
//  GPUImageCRTFilter.h
//  SNES4iOS
//
//  Created by Jake Gundersen on 11/5/12.
//
//

#import "GPUImageFilter.h"

@interface GPUImageCRTFilter : GPUImageFilter {
    GLuint CRTInputSizeUniform, CRTOutputSizeUniform;
}

@property (nonatomic, assign) CGPoint CRTInputSize;
@property (nonatomic, assign) CGPoint CRTOutputSize;

@end
