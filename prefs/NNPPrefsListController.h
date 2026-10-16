#import "NNPPrefsPrivate.h"

// Generic settings page driven by a plist in the bundle. The plist name comes from the
// "plistName" property of the specifier that opened the page (default "Root").
//
// Extra specifier properties understood by this controller:
//   dependsOn          preference key whose value controls whether this row is enabled
//   dependsEnabledWhen BOOL value of that key that enables the row
//   dependsDefault     BOOL value assumed when the key is not set
@interface NNPPrefsListController : PSListController
@end

@interface NNPRootListController : NNPPrefsListController
@end
