package TEST::Fennec::Assert::Core::Exception;
use strict;
use warnings;

use Fennec;

our $CLASS = 'Fennec::Assert::Core::Exception';

tests use_test_exception => sub {
    use_ok $CLASS;
    my $self = shift;
    can_ok( $self, qw/lives_ok dies_ok throws_ok lives_and/ );
    my $ac = anonclass( use => $CLASS );
    can_ok( $ac->class, qw/lives_ok dies_ok throws_ok lives_and/ );
};

tests lives_ok => sub {
    my $results = capture {
        lives_ok { 1 } 'lives';
        lives_ok { die ( 'xxx' )} 'dies';
        lives_ok { 1 };
    };
    is( @$results, 3, "3 results" );
    is( $results->[0]->name, "lives", "correct name" );
    is( $results->[0]->pass, 1, "passed" );
    is( $results->[1]->name, "dies", "correct name" );
    is( $results->[1]->pass, 0, "failed" );
    is( @{ $results->[1]->stderr }, 1, "1 message" );
    like(
        $results->[1]->stderr->[0],
        qr/xxx at/,
        "useful message"
    );

    is( $results->[2]->name, 'nameless test', "Automatic test name" );
};

tests dies_ok => sub {
    my $results = capture {
        dies_ok { die 'xxx' } 'pass';
        dies_ok { 1 } 'fail';
        dies_ok { die 'xxx' };
    };

    is( @$results, 3, '3 results' );
    is( $results->[0]->name, 'pass', "pass name" );
    is( $results->[0]->pass, 1, "result 1 pass" );
    is( $results->[1]->name, 'fail', "name - fail" );
    is( $results->[1]->pass, 0, "second result fail" );
    is(
        $results->[1]->stderr->[0],
        "Did not die as expected",
        "Got error"
    );
    is( $results->[2]->name, "nameless test", "automatic name" );
};

tests throws_ok => sub {
    my $results = capture {
        throws_ok { die 'xxx' } qr/xxx at/, "pass";
        throws_ok { 1 } qr/xxx/, "no die";
        throws_ok { die 'aaa' } qr/xxx at/, "wrong throw";

        throws_ok { die 'xxx' } qr/xxx at/;
        throws_ok { 1 } qr/xxx/;
        throws_ok { die 'aaa' } qr/xxx at/;
    };
    my $ln_a = ln(-6);
    my $ln_b = ln(-3);

    is( @$results, 6, "6 results" );
    is( $results->[0]->pass, 1, "pass" );
    is( $results->[0]->name, "pass", "name" );

    is( $results->[1]->pass, 0, "fail" );
    is( $results->[1]->name, "no die", "name" );
    is_deeply(
        $results->[1]->stderr,
        [ "Test did not die as expected" ],
        "Proper error"
    );

    is( $results->[2]->pass, 0, "fail" );
    is( $results->[2]->name, "wrong throw", "name" );
    is_deeply(
        $results->[2]->stderr,
        [
            "Wanted: " . qr/xxx at/,
            "Got: aaa at " . __FILE__ . " line $ln_a.\n"
        ],
        "Proper error"
    );

    is( $results->[3]->pass, 1, "pass" );
    is( $results->[3]->name, "nameless test", "name" );
    is( $results->[4]->pass, 0, "fail" );
    is( $results->[4]->name, "nameless test", "name" );
    is_deeply(
        $results->[4]->stderr,
        [ "Test did not die as expected" ],
        "Proper error"
    );

    is( $results->[5]->pass, 0, "fail" );
    is( $results->[5]->name, "nameless test", "name" );
    is_deeply(
        $results->[5]->stderr,
        [
            "Wanted: " . qr/xxx at/,
            "Got: aaa at " . __FILE__ . " line $ln_b.\n"
        ],
        "Proper error"
    );
};




1;

__END__

tester 'throws_ok';
sub throws_ok(&$;$) {
    my ( $code, $reg, $name ) = @_;
    my ( $ok, $msg ) = live_or_die( $code );
    my ( $pkg, $file, $number ) = caller;

    # If we lived
    return result(
        pass => !$ok ? 1 : 0,
        name => $name || 'nameless test',
        stderr => ["Test did not die as expected"],
    ) if $ok;

    my $match = $msg =~ $reg ? 1 : 0;
    my @diag = ("Wanted: $reg", "Got: $msg" )
        unless( $match );

    return result(
        pass => $match ? 1 : 0,
        name => $name || 'nameless test',
        stderr => \@diag,
    );
}

tester 'lives_and';
sub lives_and(&;$) {
    my ( $code, $name ) = @_;
    my ( $ok, $msg )= live_or_die( $code );
    my ( $pkg, $file, $number ) = caller;
    chomp( $msg );
    $msg =~ s/\n/ /g;
    return if $ok;

    return result(
        pass => 0,
        name => $name || 'nameless test',
        stderr => ["Test unexpectedly died: '$msg'"],
    );
}

sub live_or_die {
    my ( $code ) = @_;
    my $return = eval { $code->(); 'did not die' } || "died";
    my $msg = $@;

    if ( $return eq 'did not die' ) {
        return 1;
    }
    else {
        return 0 unless wantarray;

        if ( !$msg ) {
            carp "code died as expected, however the error is masked. This"
               . " can occur when an object's DESTROY() method calls eval";
        }

        return ( 0, $msg );
    }
}

1;
