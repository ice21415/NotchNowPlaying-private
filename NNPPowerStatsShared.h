#pragma once
#import <Foundation/Foundation.h>

// Shared by the tweak (writer) and the preferences bundle (reader).
// Stored in the preferences domain below as plain property-list values.
//
//   Hours:   array of dictionaries, one per clock hour that had AOD samples
//     h        NSNumber  hour index (unix time / 3600)
//     idleS    NSNumber  seconds with the idle clock shown
//     mediaS   NSNumber  seconds with the music player shown
//     dischS   NSNumber  seconds sampled while discharging
//     chgS     NSNumber  seconds sampled while charging
//     usedMAh  NSNumber  capacity drop while discharging (mAh)
//     pwrSum   NSNumber  sum of instantaneous whole-device power samples (mW)
//     pwrN     NSNumber  number of power samples in pwrSum
//     pct1     NSNumber  last battery percent seen in the hour
//   Battery: dictionary snapshot of the latest battery registry reading
//     percent, rawMAh, maxMAh, designMAh, cycles, tempC, voltage, charging, updated
static NSString *const NNPStatsDomain = @"com.user.notchnowplaying.stats";
static NSString *const NNPStatsHoursKey = @"Hours";
static NSString *const NNPStatsBatteryKey = @"Battery";
static const NSUInteger NNPStatsMaxHours = 240;
