package Debug::LTrace::plstrace;

use 5.010001;
use warnings;
use strict;

use Devel::Symdump;
use Hook::LexWrap;
use SHARYANTO::String::Util qw/qqquote/;
use Time::HiRes qw/gettimeofday tv_interval/;

# VERSION
# DATE

my %import_params;
my @permanent_objects;

sub import {
    shift;
    $import_params{ ${ \scalar caller } } = [@_];
}

INIT {
    while ( my ( $package, $params ) = each %import_params ) {
        push @permanent_objects, __PACKAGE__->_new( $package, @$params ) if @$params;
    }
}

# External constructor
sub new {
    return unless defined wantarray;
    my $self = shift->_new( scalar caller, @_ );
    $self;
}

# Internal constructor
sub _new {
    my ( $class, $trace_package, @params ) = @_;
    my $self;

    # Parse input parameters
    foreach my $p (@params) {
        if ($p =~ /^(-\w+)(?:=(.*))?/) {
            # option
            if ($1 eq '-t') {
                # additive options
                $self->{$1}++;
            } else {
                $self->{$1} = defined($2) ? $2 : 1;
            }
            next;
        }

        #process sub
        $p = $trace_package . '::' . $p unless $p =~ m/::/;
        push @{ $self->{subs} }, (
            $p =~ /^(.+)::\*(\*?)$/
            ? Devel::Symdump ->${ \( $2 ? 'rnew' : 'new' ) }($1)->functions()
            : $p
            );
    }

    bless $self, $class;
    $self->_start_trace();
    $self;
}

# Bind all hooks for tracing
sub _start_trace {
    my ($self) = @_;
    return unless ref $self;

    $self->{wrappers} = {};
    my @messages;

    foreach my $sub ( @{ $self->{subs} } ) {
        next if $self->{wrappers}{$sub};    # Skip already wrapped

        $self->{wrappers}{$sub} = Hook::LexWrap::wrap(
            $sub,
            pre => sub {
                pop();
                #my ( $pkg, $file, $line ) = caller(0);
                #my ($caller_sub) = ( caller(1) )[3];

                my $args = join(", ", map {$self->_esc($_)} @_);
                unshift @messages, [ "$sub($args)", [ gettimeofday() ] ];
            },
            post => sub {
                my $endtime = [gettimeofday()];
                my $wantarray = ( caller(0) )[5];
                my $call_data = shift(@messages);

                my $res = defined($wantarray) ? " = ".$self->_esc($wantarray ? pop : [pop]) : '';
                my $msg = "$call_data->[0]$res";
                if ($self->{-t}) {
                    my $time = $self->_fmttime($call_data->[1]);
                    $msg = "$time $msg";
                }
                if ($self->{-T}) {
                    $msg .= sprintf(" <%.6f>", tv_interval(
                        $call_data->[1], [gettimeofday] ));
                }
                warn "$msg\n";
            } );
    }

    # defaults
    $self->{-s} //= 32;

    $self;
}

sub _esc {
    my ($self, $data) = @_;
    if (!defined($data)) {
        "undef";
    } elsif (ref $data) {
        "$data";
    } elsif (length($data) > $self->{-s}) {
        qqquote(substr($data,0,$self->{-s}))."...";
    } else {
        qqquote($data);
    }
}

sub _fmttime {
    my ($self, $time) = @_;
    my @lt = localtime($time->[0]);
    if ($self->{-t} > 2) {
        sprintf "%d.%06d", $time->[0], $time->[1];
    } elsif ($self->{-t} > 1) {
        sprintf "%02d:%02d:%02d.%06d", $lt[2], $lt[1], $lt[0], $time->[1];
    } else {
        sprintf "%02d:%02d:%02d", $lt[2], $lt[1], $lt[0];
    }
}

1;

# TODO:
# support -s (strsize)
#
