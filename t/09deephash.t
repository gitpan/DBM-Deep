##
# DBM::Deep Test
##
use strict;
use Test;
BEGIN { plan tests => 3 }

use DBM::Deep;

##
# basic file open
##
unlink "test.db";
my $db = new DBM::Deep(
	file => "test.db"
);
if ($db->error()) {
	die "ERROR: " . $db->error();
}

##
# basic deep hash
##
$db->{company} = {};
$db->{company}->{name} = "My Co.";
$db->{company}->{employees} = {};
$db->{company}->{employees}->{"Henry Higgins"} = {};
$db->{company}->{employees}->{"Henry Higgins"}->{salary} = 90000;

ok( $db->{company}->{name} eq "My Co." );
ok( $db->{company}->{employees}->{"Henry Higgins"}->{salary} == 90000 );

##
# super deep hash
##
my $max_levels = 1000;
$db->{base_level} = {};
my $temp_db = $db->{base_level};

for (my $k=0; $k<$max_levels; $k++) {
	$temp_db->{"level".$k} = {};
	$temp_db = $temp_db->{"level".$k};
}
$temp_db->{deepkey} = "deepvalue";
undef $temp_db;

##
# start over, now validate all levels
##
$temp_db = $db->{base_level};
for (my $k=0; $k<$max_levels; $k++) {
	if ($temp_db) { $temp_db = $temp_db->{"level".$k}; }
}
ok( $temp_db && ($temp_db->{deepkey} eq "deepvalue") );

undef $temp_db;

##
# close, delete file, exit
##
undef $db;
unlink "test.db";
exit(0);
