//
//  GPUImageDotnBloomFilter.m
//  SNES4iOS
//
//  Created by Jake Gundersen on 11/5/12.
//
//Dot 'n bloom shader
//Author: Themaister
//License: Public domain

#import "GPUImageDotnBloomFilter.h"

NSString *const kGPUImageDotnBloomNearbyTexelSamplingVertexShaderString = SHADER_STRING
(
 attribute vec4 position;
 attribute vec4 inputTextureCoordinate;
 
 uniform highp float texelWidth;
 uniform highp float texelHeight;
 
 varying vec2 pixel_no;
 
 varying vec2 textureCoordinate;
 varying vec2 leftTextureCoordinate;
 varying vec2 rightTextureCoordinate;
 
 varying vec2 topTextureCoordinate;
 varying vec2 topLeftTextureCoordinate;
 varying vec2 topRightTextureCoordinate;
 
 varying vec2 bottomTextureCoordinate;
 varying vec2 bottomLeftTextureCoordinate;
 varying vec2 bottomRightTextureCoordinate;
 
 void main()
 {
     gl_Position = position;
     
     vec2 widthStep = vec2(texelWidth, 0.0);
     vec2 heightStep = vec2(0.0, texelHeight);
     vec2 widthHeightStep = vec2(texelWidth, texelHeight);
     vec2 widthNegativeHeightStep = vec2(texelWidth, -texelHeight);
     
     pixel_no = vec2(1.0/ texelWidth, 1.0/texelHeight) * inputTextureCoordinate.xy;
     
     textureCoordinate = inputTextureCoordinate.xy;
     leftTextureCoordinate = inputTextureCoordinate.xy - widthStep;
     rightTextureCoordinate = inputTextureCoordinate.xy + widthStep;
     
     topTextureCoordinate = inputTextureCoordinate.xy - heightStep;
     topLeftTextureCoordinate = inputTextureCoordinate.xy - widthHeightStep;
     topRightTextureCoordinate = inputTextureCoordinate.xy + widthNegativeHeightStep;
     
     bottomTextureCoordinate = inputTextureCoordinate.xy + heightStep;
     bottomLeftTextureCoordinate = inputTextureCoordinate.xy - widthNegativeHeightStep;
     bottomRightTextureCoordinate = inputTextureCoordinate.xy + widthHeightStep;
 }
 );


NSString *const kGPUImageDotnBloomFragmentShaderString = SHADER_STRING
(
 precision highp float;
 
 uniform sampler2D inputImageTexture;
 
 varying vec2 textureCoordinate;
 varying vec2 leftTextureCoordinate;
 varying vec2 rightTextureCoordinate;
 
 varying vec2 topTextureCoordinate;
 varying vec2 topLeftTextureCoordinate;
 varying vec2 topRightTextureCoordinate;
 
 varying vec2 bottomTextureCoordinate;
 varying vec2 bottomLeftTextureCoordinate;
 varying vec2 bottomRightTextureCoordinate;
 
 varying vec2 pixel_no;
 
 const float gamma = 2.4;
 const float shine = 0.05;
 const float blend = 0.65;
 
 float dist(vec2 coord, vec2 source)
 {
     vec2 delta = coord - source;
     return sqrt(dot(delta, delta));
 }
 
 float color_bloom(vec3 color)
 {
     const vec3 gray_coeff = vec3(0.30, 0.59, 0.11);
     float bright = dot(color, gray_coeff);
     return mix(1.0 + shine, 1.0 - shine, bright);
 }
 
 vec3 lookup(float offset_x, float offset_y, vec2 coord)
 {
     vec2 offset = vec2(offset_x, offset_y);
     vec3 color = texture2D(inputImageTexture, coord).rgb;
     float delta = dist(fract(pixel_no), offset + vec2(0.5));
     return color * exp(-gamma * delta * color_bloom(color));
 }
 
 void main()
 {
     vec3 mid_color = lookup(0.0, 0.0, textureCoordinate);
     vec3 color = vec3(0.0);
     color += lookup(-1.0, -1.0, topLeftTextureCoordinate);
     color += lookup( 0.0, -1.0, topTextureCoordinate);
     color += lookup( 1.0, -1.0, topRightTextureCoordinate);
     color += lookup(-1.0,  0.0, leftTextureCoordinate);
     color += mid_color;
     color += lookup( 1.0,  0.0, rightTextureCoordinate);
     color += lookup(-1.0,  1.0, bottomLeftTextureCoordinate);
     color += lookup( 0.0,  1.0, bottomTextureCoordinate);
     color += lookup( 1.0,  1.0, bottomRightTextureCoordinate);
     vec3 out_color = mix(1.2 * mid_color, color, blend);
     
     gl_FragColor = vec4(out_color, 1.0);
 }
 );

@implementation GPUImageDotnBloomFilter

- (id)init;
{
    if (!(self = [super initWithVertexShaderFromString:kGPUImageDotnBloomNearbyTexelSamplingVertexShaderString fragmentShaderFromString:kGPUImageDotnBloomFragmentShaderString]))
    {
		return nil;
    }
    
    texelWidthUniform = [filterProgram uniformIndex:@"texelWidth"];
    texelHeightUniform = [filterProgram uniformIndex:@"texelHeight"];
    
    return self;
}

@end
