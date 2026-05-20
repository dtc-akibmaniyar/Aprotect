trigger AccountTaxRegionTrigger on Account (before insert, before update) {
    AccountTaxRegionHandler.autoPopulateTaxRegion(Trigger.new, Trigger.oldMap);
}