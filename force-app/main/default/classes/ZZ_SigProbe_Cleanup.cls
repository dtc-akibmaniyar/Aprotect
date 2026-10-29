public with sharing class ZZ_SigProbe_Cleanup implements Schedulable {
    public static final Integer DEFAULT_AGE_MINUTES = 10;

    public void execute(SchedulableContext ctx) {
        run(DEFAULT_AGE_MINUTES);
    }

    public static Integer run(Integer ageMinutes) {
        ZZ_SigProbe_Nc.R found =
            ZZ_SigProbe_Nc.findBySoql('SELECT Id, Name, CreatedDate FROM StaticResource WHERE Name LIKE \'SIGTMP%\'');
        if (found.code != 200) {
            return -1;
        }
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(found.body);
        List<Object> recs = (List<Object>) body.get('records');
        Integer deleted = 0;
        DateTime cutoff = System.now().addMinutes(-ageMinutes);
        for (Object o : recs) {
            Map<String, Object> m = (Map<String, Object>) o;
            String created = (String) m.get('CreatedDate');
            if (created == null) {
                continue;
            }
            DateTime cd = (DateTime) JSON.deserialize('"' + created + '"', DateTime.class);
            if (ageMinutes == 0 || cd < cutoff) {
                ZZ_SigProbe_Nc.R d = ZZ_SigProbe_Nc.del((String) m.get('Id'));
                if (d.code == 204 || d.code == 200) {
                    deleted++;
                }
            }
        }
        return deleted;
    }
}