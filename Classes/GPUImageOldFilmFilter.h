//
//  GPUImageOldFilmFilter.h
//  SNES4iOS
//
//  Created by Jake Gundersen on 11/5/12.
//
//

#import "GPUImageFilter.h"

@interface GPUImageOldFilmFilter : GPUImageFilter {
    GLuint timeUniform;
}

@property (nonatomic, readwrite) float time;

@end
