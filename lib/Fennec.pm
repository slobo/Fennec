package Fennec;
use strict;
use warnings;

use Test::Builder;
use Cwd qw/cwd/;
use File::Temp qw/tempfile/;
use Carp;
use Scalar::Util 'blessed';
use List::Util 'shuffle';
use Fennec::Grouping;
use Fennec::Test;
use Sub::Uplevel;
use autodie;

#{{{ POD

=pod

=head1 NAME

Fennec - A more modern testing framework for perl

=head1 DESCRIPTION

Fennec is a test framework that addresses several complains I have heard,
or have myself issued forth about perl testing. It is still based off
L<Test::Builder> and uses a lot of existing test tools.

Please see L<Fennec::Specification> for more details.

=head1 WHY FENNEC

Fennec is intended to do for perl testing what L<Moose> does for OOP. It makes
all tests classes, and defining test cases and test sets within that class is
simple. In traditional perl testing you would have to manually loop if you
wanted to runa set of tests multiple times in different cases, it is difficult
to make forking tests, and you have limited options for more advanced test
frameworks.

Fennec runs around taking care of the details for you. You simply need to
specify your sets, your cases, and weither or not you want the sets and cases
to fork, run in parrallel or in sequence. Test sets and cases are run in random
order by default. Forking should just plain work without worrying about the
details.

The Fennec fox is a hyper creature, it does a lot of running around, because of
this the name fits. As well Fennec is similar in idea to Moose, so why not name
it after another animal? Finally I already owned the namespace for a dead
project, and the namespace I wanted was taken.

=head1 EARLY VERSION WARNING

This is VERY early version. Fennec does not run yet.

Please go to L<http://github.com/exodist/Fennec> to see the latest and
greatest.

=head1 DOCUMENTATION

This is the internal Fennec API documentation. For more detailed end-user
documentation please see L<Fennec::Manual>.

=head1 IMPORT

Fennec is the only module someone using Fennec should have to 'use'.
The parameters provided to import() on use do a significant portion of the test
setup. When Fennec is used it will instantate a singleton of the calling
class and store it as a test to be run.

Using Fennec also automatically adds 'Fennec::Test' to the
calling classes @ISA.

=head1 IMPORT OPTIONS

    use Fennec %OPTIONS;

These are the options supported, all are optional.

=over 4

=item testing => 'My::Module'

Used to specify the module to be tested by this test class. This module will be
loaded, and it's import will be run with the test class as caller. This is a
lot like use_ok(), the difference is that 'use' forces a BEGIN{} block.

Anything exported by the tested module will be loaded before the rest of the
test class is compiled. This allows the use of exported functions with
prototypes and the use of constants within the test class.

    use Fennec testing => 'My::Module';

=item import_args => [ @ARGS ]

Specify the arguments to provide the import() method of the module specified by
'testing => ...'.

    use Fennec testing     => 'My::Module',
                    import_args => [ 'a', 'b' ];

=item plugins => [ 'want', 'another', '-do_not_want', '-this_either' ]

Specify which plugins to load or prevent loading. By default 'More', 'Simple',
'Exception', and 'Warn' plugins are loaded. You may specify any additional
plugins. You may also prevent the loadign of a default plugin by listing it
prefixed by a '-'.

See L<Fennec::Plugin> for more information about plugins.

See Also L<Fennec::Plugin::Simple>, L<Fennec::Plugin::More>,
L<Fennec::Plugin::Exception>, L<Fennec::Plugin::Warn>

=item all others

All other arguments will be passed into the constructor for your test class,
which is defined in L<Fennec::Test>.

=back

=head1 CONSTRUCTORS

=over 4

=cut

#}}}

our $VERSION = "0.005";
our $SINGLETON;
our $TB = Test::Builder->new;
our @DEFAULT_PLUGINS = qw/Warn Exception More Simple/;

#{{{ IMPORT STUFF
sub import {
    my $class = shift;
    my %options = @_;
    my ( $package, $filename ) = caller();

    if ( my $get_from = $options{ testing }) {
        eval "require $get_from" || croak( $@ );

        my ( $level, $sub, @args ) = $class->_get_import( $get_from, $package );
        next unless $sub;

        push @args => @{ $options{ import_args }} if $options{ import_args };

        $level ? uplevel( $level, $sub, @args )
               : $sub->( @args );
    }

    {
        no strict 'refs';
        push @{ $package . '::ISA' } => 'Fennec::Test';
    }

    $class->_export_plugins( $package, $options{ plugins } );
    Fennec::Grouping->export_to( $package );

    my $self = $class->get;
    my $test = $package->new( %options, filename => $filename );
    $self->add_test( $test );
    return $test;
}

sub _get_import {
    my $class = shift;
    my ($get_from, $send_to) = @_;
    my $import = $get_from->can( 'import' );
    return unless $import;

    return ( 1, $import, $get_from )
        unless $get_from->isa( 'Exporter' );

    return ( 1, $import, $get_from )
        if $import != Exporter->can( 'import' );

    return ( 0, $get_from->can('export_to_level'), $get_from, 1, $send_to );
}

sub _export_plugins {
    my $class = shift;
    my ( $package, $specs ) = @_;
    my @plugins = @DEFAULT_PLUGINS;

    if ( $specs ) {
        my %remove;
        for ( @$specs ) {
            m/^-(.*)$/ ? ($remove{$1}++)
                       : (push @plugins => $_);
        }

        my %seen;
        @plugins = grep { !($seen{$_}++ || $remove{$_}) } @plugins;
    }

    for my $plugin ( @plugins ) {
        my $name = "Fennec\::Plugin\::$plugin";
        eval "require $name" || die( $@ );
        $name->export_to( $package );
    }
}
#}}}

=item $ts = $class->new()

Takes no arguments. Returns the Fennec singleton object.

=item $ts = $class->get()

Aloas to new, as a singleton get() makes more sense in many cases.

=cut

sub new {
    my $class = shift;
    return $SINGLETON if $SINGLETON;

    # Create socket
    my ( $fh, $file ) = tempfile( cwd() . "/.test-suite.$$.XXXX", UNLINK => 1 );
    require IO::Socket::UNIX;
    close( $fh ) || die( $! );
    unlink( $file );
    my $socket = IO::Socket::UNIX->new(
        Listen => 1,
        Local => $file,
    ) || die( $! );

    $SINGLETON = bless(
        {
            parent_pid => $$,
            pid => $$,
            socket => $socket,
            _socket_file => $file,
        },
        $class
    );
    return $SINGLETON;
}

sub get { goto &new };

=back

=head1 OBJECT METHODS

=over 4

=item $ts->add_test( $test )

Add a <Fennec::Test> object to be tested when run is called.

=cut

sub add_test {
    my $self = shift;
    my ( $test ) = @_;
    my $package = blessed( $test );

    croak "$package has already been added as a test"
        if $self->tests->{ $package };

    $self->tests->{ $package } = $test;
}

=item $test = $ts->get_test( $package )

Get the singleton test for the specified package.

=cut

sub get_test {
    my $self = shift;
    my ( $package ) = @_;
    return $self->tests->{ $package };
}

=item $tests = $ts->tests

Get the hashref storing all the package => $test relationships.

=cut

sub tests {
    my $self = shift;
    $self->{ tests } ||= {};
    return $self->{ tests };
}

=item $pid = $ts->pid()

Returns the current process id as provided by $$.

=cut

sub pid {
    my $self = shift;
    $self->{ pid } = $$ if @_;
    return $self->{ pid };
}

=item $pid = $ts->parent_pid()

Returns the pid of the process which instantiated the Fennec singleton.

=cut

sub parent_pid {
    my $self = shift;
    return $self->{ parent_pid };
}

=item $bool = $ts->is_parent()

Returns true if the current process is the process in which the singleton was
instantiated.

=cut

sub is_parent {
    my $self = shift;
    return ( $$ == $self->parent_pid ) ? 1 : 0;
}

=item $bool = $ts->is_running()

Check if the tests are currently running.

=cut

sub is_running {
    my $self = shift;
    ($self->{ is_running }) = @_ if @_;
    return $self->{ is_running };
}

=item $ts->result({ result => $BOOL, name => 'My Test', ... })

Issue a test result for output. You almost certainly do not want to call this
directly. If you are witing a plugin please see L<Fennec::Plugin> or the
PLUGINS section of L<Fennec::Manual>.

=cut

sub result {
    my $self = shift;
    croak( "Testing has not been started" )
        unless $self->is_running;

    return $self->_handle_result( @_ )
        if $self->is_parent;

    $self->_send_result( @_ );
}

=item $ts->diag( "message 1", "message 2", ... )

An interface to Test::Builder->diag() (which has been overriden). You can use
this to report diagnostics information.

=cut

sub diag {
    my $self = shift;
    $self->result({ diag => \@_ });
}

=item $ts->run()

Run the tests. Will die if they are already running, or if the process is ntot
he parent.

=cut

sub run {
    my $self = shift;
    croak "Already running"
        if $self->is_running;
    croak "run() may only be run fromt he parent process."
        unless $self->is_parent;

    $self->is_running( 1 );
    my $listen = $self->_socket;

    for my $test ( shuffle values %{ $self->tests }) {
        $test->run();
    }

    $TB->done_testing;
}

sub _handle_result {
    my $class = shift;
    my ($result) = @_;
    if (( keys %$result ) == 1 && $result->{ diag }) {
        $TB->diag( $result->{ diag });
        return 1;
    }

    $TB->real_ok($result->{ result } || 0, $result->{ name });
    $TB->real_diag( $_ ) for @{ $result->{ debug } || []};
}

sub _send_result {
    confess( "Forking not yet implemented" );
}

sub _socket_file {
    my $self = shift;
    return $self->{ _socket_file },
}

sub _socket {
    my $self = shift;
    return $self->{ socket } if $$ == $self->parent_pid;

    # If we are in a new child clear existing sockets and make new ones
    unless ( $$ == $self->pid ) {
        delete $self->{ socket };
        delete $self->{ client_socket };
        $self->pid( 1 ); #Set pid.
    }

    $self->{ client_socket } ||= IO::Socket::UNIX->new(
        Peer => $self->_socket_file,
    );

    return $self->{ client_socket };
}

sub DESTROY {
    my $self = shift;
    my $socket = $self->_socket;
    close( $socket ) if $socket;
    unlink( $self->_socket_file ) if $self->is_parent;
}

1;

=back

=head1 AUTHORS

Chad Granum L<exodist7@gmail.com>

=head1 COPYRIGHT

Copyright (C) 2010 Chad Granum

Fennec is free software; Standard perl licence.

Fennec is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE.  See the license for more details.