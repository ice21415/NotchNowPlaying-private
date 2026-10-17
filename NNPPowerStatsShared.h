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
//     usedMAh, pwrSum, pwrN: legacy estimates, retained but excluded by reader
//     usedMAh2 NSNumber  integrated discharge current (mAh)
//     dischS2  NSNumber  valid electrical integration seconds
//     energyMWs NSNumber time integral of whole-device power (mW*s)
//     powerS   NSNumber  valid power integration seconds; mean = energyMWs/powerS
//     usedPct2 NSNumber  integrated mAh / contemporaneous full capacity * 100
//     pctS2    NSNumber  valid percentage integration seconds
//     pct1     NSNumber  last battery percent seen in the hour
//   Battery: dictionary snapshot of the latest battery registry reading
//     percent, rawMAh, maxMAh, designMAh, cycles, tempC, voltage, charging, updated
static NSString *const NNPStatsDomain = @"com.user.notchnowplaying.stats";
static NSString *const NNPStatsHoursKey = @"Hours";
static NSString *const NNPStatsBatteryKey = @"Battery";
static const NSUInteger NNPStatsMaxHours = 240;
