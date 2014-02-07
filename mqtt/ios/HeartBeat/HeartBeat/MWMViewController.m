//
//  MWMViewController.m
//  HeartBeat
//
//  Created by Jeff Mesnil on 07/02/2014.
//  Copyright (c) 2014 Mobile & Web Messaging. All rights reserved.
//

#import "MWMViewController.h"
#import <MQTTKit.h>

#define kMqttHost @"test.mosquitto.org"
#define kHeartRateTopic @"/MQTTMWM/HeartRate/%@"
#define kAlertTopic @"/MQTTMWM/HeartRate/%@/alerts"

@interface MWMViewController () <MQTTClientDelegate>

@property (weak, nonatomic) IBOutlet UILabel *clientIDLabel;
@property (weak, nonatomic) IBOutlet UILabel *rateLabel;
@property (strong, nonatomic) MQTTClient *mqttClient;
@property (strong, nonatomic) NSString *clientID;

@end

@implementation MWMViewController

NSTimer *rateTimer;
// initialize the current rate at 70bpm
NSInteger currentRate = 70;

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.clientID = [UIDevice currentDevice].identifierForVendor.UUIDString;
    NSLog(@"Client identifier is %@", self.clientID);
    self.clientIDLabel.text = self.clientID;
    
    // get a weak reference of self to avoid a retain/release cycle
    // between the controller and the timer
    __weak id weakSelf = self;
    rateTimer = [NSTimer scheduledTimerWithTimeInterval:2.0f
                                                 target:weakSelf
                                               selector:@selector(heartbeat:)
                                               userInfo:nil
                                                repeats:YES];
    [self connect];
}

- (void)dealloc
{
    [rateTimer invalidate];
    [self disconnect];
}

#pragma mark - Heart beat simulator

- (void) heartbeat:(NSTimer *)timer
{
    // use a low pass filter with a random to change the heart beat
    float factor = 0.1;
    NSInteger newValue = 80 - arc4random_uniform(20);
    currentRate = floor(newValue * factor + currentRate * (1 - factor));
    self.rateLabel.text = [NSString stringWithFormat:@"%ld\nbpm", (long)currentRate];
    [self send:currentRate];
}

#pragma mark - MQTT actions

- (void)connect
{
    self.mqttClient = [[MQTTClient alloc] initWithClientId:self.clientID];
    // Override point for customization after application launch.
    self.mqttClient.delegate = self;
    [self.mqttClient connectToHost:kMqttHost];
}

- (void)disconnect
{
    [self.mqttClient disconnect];
}

- (void)send:(NSInteger)rate
{
    [self.mqttClient publishString:[NSString stringWithFormat:@"%ld", (long)rate]
                           toTopic:[NSString stringWithFormat:kHeartRateTopic, self.clientID]
                           withQos:0
                            retain:NO];
}

#pragma mark - MQTTClientDelegate

- (void)client:(MQTTClient *)client
    didConnect:(NSUInteger)code
{
    // once connect, subscribe to the client's alerts topic
    NSString *alertTopic = [NSString stringWithFormat:kAlertTopic, self.clientID];
    [client subscribe:alertTopic
              withQos:0];
}

- (void)client:(MQTTClient *)client didReceiveMessage:(MQTTMessage *)message
{
    NSString *alertTopic = [NSString stringWithFormat:kAlertTopic, self.clientID];
    if ([alertTopic isEqualToString:message.topic]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self warnUser];
        });
    }
}

# pragma mark - UI Actions

// Warn the user by changing the view's background color to red for 2 seconds
- (void)warnUser
{
    // keep a reference to the original color
    UIColor *originalColor = self.view.backgroundColor;
    
    [UIView animateWithDuration:0.5
                          delay:0.0
                        options:0
                     animations:^{
                         // change it to red
                         self.view.backgroundColor = [UIColor redColor];
                     }
                     completion:^(BOOL finished) {
                         // after a delay of 2 seconds, revert it to the original color
                         [UIView animateWithDuration:0.5
                                               delay:2
                                             options:0
                                          animations:^{
                                              self.view.backgroundColor = originalColor;
                                          }
                                          completion:nil];
                     }];
}

@end
