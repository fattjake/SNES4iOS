//
//  iCadeViewController.m
//  SNES4iOS
//
//  Created by Shawn Allen on 9/28/12.
//
//

#import "iCadeViewController.h"

@interface iCadeViewController ()

- (void)setState:(BOOL)state forButton:(iCadeState)button;

@end

@implementation iCadeViewController

#pragma mark -
#pragma mark Class extension

/*
 
    Button mapping is tricky - the ControlPad buttons don't match the iCade buttons, 
    and they don't match the SNES Controller, so here's my model:
 
    iCade Buttons to SNES Controller
    5 = Y
    6 = B
    7 = X
    8 = A
    9 = L
    10 = R
 
    iCade doesnt have start/select, so I'm using the E1 & E2 (these are in the trigger positions, not great, but change it if you want!
 
    E1 = Select
    E2 = Start
 
    ControlPad to SNES
 
    A        SELECT
    B        LEFT SHOULDER
    C        START
    D        RIGHT SHOULDER
    E        Y
    F        A
    G        B
    H        X

    iCade Numbers to SCarnie's letters (my iCade mobile has numbers instead of letters) - 
 
    5 - A
    6 - B
    7 - C
    8 - D
    9 - E
    10 - F
    E1 - G
    E2 - H
 
    
    SNES - ControlPod - iCade
 
    A - F - 8/D
    B - G - 6/B
    X - H - 7/C
    Y - E - 5/A
    L - B - 9/E
    R - D - 10/F
    Strt - C - E2/H
    Slct - A - E1/G
 
 
 */

- (void)setState:(BOOL)state forButton:(iCadeState)button;
{
    ControlPadState padButton = ControlPadStateNone;
    
    switch (button) {
        case iCadeButtonA:
            padButton = ControlPadStateButtonE;
            break;
        case iCadeButtonB:
            padButton = ControlPadStateButtonG;
            break;
        case iCadeButtonC:
            padButton = ControlPadStateButtonH;
            break;
        case iCadeButtonD:
            padButton = ControlPadStateButtonF;
            break;
        case iCadeButtonE:
            padButton = ControlPadStateButtonB;
            break;
        case iCadeButtonF:
            padButton = ControlPadStateButtonD;
            break;
        case iCadeButtonG:
            padButton = ControlPadStateButtonA;
            break;
        case iCadeButtonH:
            padButton = ControlPadStateButtonC;
            break;
        case iCadeJoystickUp:
            padButton = ControlPadStateUp;
            break;
        case iCadeJoystickRight:
            padButton = ControlPadStateRight;
            break;
        case iCadeJoystickDown:
            padButton = ControlPadStateDown;
            break;
        case iCadeJoystickLeft:
            padButton = ControlPadStateLeft;
            break;
        default:
            break;
    }
    
    [[self delegate] padChangedState:padButton pressed:state];
}

#pragma mark -
#pragma mark UIViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    iCadeReaderView *control = [[iCadeReaderView alloc] initWithFrame:CGRectZero];
    [[self view] addSubview:control];
    [control setActive:YES];
    [control setDelegate:self];
}

#pragma mark -
#pragma mark iCadeEventDelegate

- (void)buttonDown:(iCadeState)button;
{
    [self setState:YES forButton:button];
}

- (void)buttonUp:(iCadeState)button;
{
    [self setState:NO forButton:button];
}

@end
