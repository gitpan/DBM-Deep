##
# Makefile.PL for DBM::Deep
##

use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'	=> 'DBM::Deep',
    'VERSION_FROM' => 'Deep.pm',
    'PREREQ_PM' => {
    	Digest::MD5 => 1.0
    }
);
