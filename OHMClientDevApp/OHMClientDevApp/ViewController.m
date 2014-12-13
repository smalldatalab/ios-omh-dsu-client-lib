//
//  ViewController.m
//  OHMClientDevApp
//
//  Created by Charles Forkish on 12/13/14.
//  Copyright (c) 2014 Open mHealth. All rights reserved.
//

#import "ViewController.h"

#import <OMHClient/OMHClient.h>

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    OMHDataPoint *dataPoint = [OMHDataPoint templateDataPoint];
    NSLog(@"Data Point: %@", dataPoint);
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
