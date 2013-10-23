#import "OutlineItem.h"

@implementation OutlineItem

+ (ETEntityDescription*)newEntityDescription
{
    ETEntityDescription *outlineEntity = [ETEntityDescription descriptionWithName: @"OutlineItem"];
    [outlineEntity setParent: (id)@"Anonymous.COContainer"];

	ETPropertyDescription *isShared = [ETPropertyDescription descriptionWithName: @"isShared"
                                                                                 type: (id)@"BOOL"];
    [isShared setPersistent: YES];
	
    ETPropertyDescription *labelProperty = [ETPropertyDescription descriptionWithName: @"label"
                                                                                 type: (id)@"Anonymous.NSString"];
    [labelProperty setPersistent: YES];
    
    ETPropertyDescription *contentsProperty =
    [ETPropertyDescription descriptionWithName: @"contents" type: (id)@"Anonymous.OutlineItem"];
	
    [contentsProperty setPersistent: YES];
    [contentsProperty setMultivalued: YES];
    [contentsProperty setOrdered: YES];
    
    ETPropertyDescription *parentContainerProperty =
    [ETPropertyDescription descriptionWithName: @"parentContainer" type: (id)@"Anonymous.OutlineItem"];
    
    [parentContainerProperty setIsContainer: YES];
    [parentContainerProperty setMultivalued: NO];
    [parentContainerProperty setOpposite: (id)@"Anonymous.OutlineItem.contents"];
    
    ETPropertyDescription *parentCollectionsProperty =
    [ETPropertyDescription descriptionWithName: @"parentCollections" type: (id)@"Anonymous.Tag"];
    
    [parentCollectionsProperty setMultivalued: YES];
    [parentCollectionsProperty setOpposite: (id)@"Anonymous.Tag.contents"];
    
    [outlineEntity setPropertyDescriptions: A(isShared, labelProperty, contentsProperty, parentContainerProperty, parentCollectionsProperty)];

    return outlineEntity;
}

- (NSString *)contentKey
{
	return @"contents";
}

- (BOOL)isShared
{
	return [self valueForVariableStorageKey: @"isShared"];
}

- (void)setIsShared:(BOOL)isShared
{
	[self willChangeValueForProperty: @"isShared"];
	[self setValue: @(isShared) forVariableStorageKey: @"isShared"];
	[self didChangeValueForProperty: @"isShared"];
}

// FIXME: Fix COObject+Accessors to support overriding read-only properties as read-write
//@dynamic isShared;
@dynamic label;
@dynamic contents;
@dynamic parentContainer;
@dynamic parentCollections;
@dynamic checked;

@end
