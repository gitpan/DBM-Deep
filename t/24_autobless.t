use strict;

{
    package Foo;

    sub export { 'export' };
    sub foo { 'foo' };
}

use Test::More tests => 64;
use t::common qw( new_fh );

use_ok( 'DBM::Deep' );

my ($fh, $filename) = new_fh();
{
    my $db = DBM::Deep->new(
        file     => $filename,
        autobless => 1,
    );

    my $obj = bless {
        a => 1,
        b => [ 1 .. 3 ],
    }, 'Foo';

    $db->{blessed} = $obj;
    is( $db->{blessed}{a}, 1 );
    is( $db->{blessed}{b}[0], 1 );
    is( $db->{blessed}{b}[1], 2 );
    is( $db->{blessed}{b}[2], 3 );

    my $obj2 = bless [
        { a => 'foo' },
        2,
    ], 'Foo';
    $db->{blessed2} = $obj2;

    is( $db->{blessed2}[0]{a}, 'foo' );
    is( $db->{blessed2}[1], '2' );

    $db->{unblessed} = {};
    $db->{unblessed}{a} = 1;
    $db->{unblessed}{b} = [];
    $db->{unblessed}{b}[0] = 1;
    $db->{unblessed}{b}[1] = 2;
    $db->{unblessed}{b}[2] = 3;

    is( $db->{unblessed}{a}, 1 );
    is( $db->{unblessed}{b}[0], 1 );
    is( $db->{unblessed}{b}[1], 2 );
    is( $db->{unblessed}{b}[2], 3 );
}

{
    my $db = DBM::Deep->new(
        file     => $filename,
        autobless => 1,
    );

    my $obj = $db->{blessed};
    isa_ok( $obj, 'Foo' );
    can_ok( $obj, 'export', 'foo' );
    ok( !$obj->can( 'STORE' ), "... but it cannot 'STORE'" );

    is( $obj->{a}, 1 );
    is( $obj->{b}[0], 1 );
    is( $obj->{b}[1], 2 );
    is( $obj->{b}[2], 3 );

    my $obj2 = $db->{blessed2};
    isa_ok( $obj, 'Foo' );
    can_ok( $obj, 'export', 'foo' );
    ok( !$obj->can( 'STORE' ), "... but it cannot 'STORE'" );

    is( $obj2->[0]{a}, 'foo' );
    is( $obj2->[1], '2' );

    is( $db->{unblessed}{a}, 1 );
    is( $db->{unblessed}{b}[0], 1 );
    is( $db->{unblessed}{b}[1], 2 );
    is( $db->{unblessed}{b}[2], 3 );

    $obj->{c} = 'new';
    is( $db->{blessed}{c}, 'new' );
}

{
    my $db = DBM::Deep->new(
        file     => $filename,
        autobless => 1,
    );
    is( $db->{blessed}{c}, 'new' );

    my $structure = $db->export();
    
    my $obj = $structure->{blessed};
    isa_ok( $obj, 'Foo' );
    can_ok( $obj, 'export', 'foo' );
    ok( !$obj->can( 'STORE' ), "... but it cannot 'STORE'" );

    is( $obj->{a}, 1 );
    is( $obj->{b}[0], 1 );
    is( $obj->{b}[1], 2 );
    is( $obj->{b}[2], 3 );

    my $obj2 = $structure->{blessed2};
    isa_ok( $obj, 'Foo' );
    can_ok( $obj, 'export', 'foo' );
    ok( !$obj->can( 'STORE' ), "... but it cannot 'STORE'" );

    is( $obj2->[0]{a}, 'foo' );
    is( $obj2->[1], '2' );

    is( $structure->{unblessed}{a}, 1 );
    is( $structure->{unblessed}{b}[0], 1 );
    is( $structure->{unblessed}{b}[1], 2 );
    is( $structure->{unblessed}{b}[2], 3 );
}

{
    my $db = DBM::Deep->new(
        file     => $filename,
        autobless => 0,
    );

    my $obj = $db->{blessed};
    isa_ok( $obj, 'DBM::Deep' );
    can_ok( $obj, 'export', 'STORE' );
    ok( !$obj->can( 'foo' ), "... but it cannot 'foo'" );

    is( $obj->{a}, 1 );
    is( $obj->{b}[0], 1 );
    is( $obj->{b}[1], 2 );
    is( $obj->{b}[2], 3 );

    my $obj2 = $db->{blessed2};
    isa_ok( $obj2, 'DBM::Deep' );
    can_ok( $obj2, 'export', 'STORE' );
    ok( !$obj2->can( 'foo' ), "... but it cannot 'foo'" );

    is( $obj2->[0]{a}, 'foo' );
    is( $obj2->[1], '2' );

    is( $db->{unblessed}{a}, 1 );
    is( $db->{unblessed}{b}[0], 1 );
    is( $db->{unblessed}{b}[1], 2 );
    is( $db->{unblessed}{b}[2], 3 );
}

my ($fh2, $filename2) = new_fh();
{
    my $db = DBM::Deep->new(
        file     => $filename2,
        autobless => 1,
    );
    my $obj = bless {
        a => 1,
        b => [ 1 .. 3 ],
    }, 'Foo';

    $db->import( { blessed => $obj } );
}

{
    my $db = DBM::Deep->new(
        file     => $filename2,
        autobless => 1,
    );

    my $blessed = $db->{blessed};
    isa_ok( $blessed, 'Foo' );
    is( $blessed->{a}, 1 );
}

{
	##
	# test blessing hash into short named class (Foo), then re-blessing into
	# longer named class (FooFoo) and replacing key in db file, then validating
	# content after that point in file to check for corruption.
	##
    my ($fh3, $filename3) = new_fh();
    my $db = DBM::Deep->new(
        file     => $filename3,
        autobless => 1,
    );

    my $obj = bless {}, 'Foo';

    $db->{blessed} = $obj;
    $db->{after} = "hello";
    
    my $obj2 = bless {}, 'FooFoo';
    
    $db->{blessed} = $obj2;

    is( $db->{after}, "hello" );
}
