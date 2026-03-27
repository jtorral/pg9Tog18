
## List of scripts

The following detail what the scripts function are for this repo when migrating Postgres environemnets.

**`libraries.sh`** will check for existing preloaded libraries which may need to be configured on the target server in order to load extensions and match what is in the source server.

**`extensions.sh`** will generate the create extension sql’s of existing extension on the source server to be used on the target server. 

**`aggreagatesPg9.sh`** will run against the Postgres 9 database instance, identify custom aggregate functions with incompatible types , generate a sql to drop and recreate them on the target server.  Do not run this until you modify the generated sql to include the proper object type.  This is just to make life easy and not have to find all the function definitions.

**`aggregatesPg11.sh`** which can be used for testing against postgres versions >= 11.
oidchecks.sh will find tables that use old OID’s and generate the necessary alter table commands to make them compatible with newer versions of Postgres.

**`identity.sh`** will generate the alter table commands necessary for logical replication. Since logical replication requires primary keys, this script will create the necessary replica identity using existing unique indexes or creating full replica identities.

It is important to know that libraries.sh should be executed and have the results applied to the target server before extensions.sh due to the fact that some extensions may require preloaded shared libraries.


**`pgList`** which contains the lists of postgres servers and ports to check. 

The file format is as follows:
**`pghost:port`**


I used docker containers all of which use localhost for the postgres host but are addressable via a unique port.  Therefore, when you see examples from pgList, the hosts names are represented by localhost.  In your environment, thos woulkd  be a postgres host name or I.P address.


