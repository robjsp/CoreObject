#import <CoreObject/COEdit.h>

@interface COEditDeleteBranch : COEdit
{
    ETUUID *_branchUUID;
}

@property (readwrite, nonatomic, copy) ETUUID *branchUUID;

@end