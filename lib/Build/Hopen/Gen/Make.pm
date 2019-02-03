# Build::Hopen::Gen::Make - generator for a generic make(1).
package Build::Hopen::Gen::Make;
use Build::Hopen qw(:default $QUIET);
use Build::Hopen::Base;
use parent 'Exporter';

our $VERSION = '0.000005'; # TRIAL

use Hash::Ordered;

use parent 'Build::Hopen::Gen';
use Class::Tiny {
    targets => sub { Hash::Ordered->new() }
};

use Build::Hopen::Phases qw(is_last_phase);
use Getargs::Mixed;

# Docs {{{1

=head1 NAME

Build::Hopen::Gen::Make - hopen generator for simple Makefiles

=head1 SYNOPSIS

This generator makes a Makefile that does its best to run on cmd.exe or sh(1).

=head1 ATTRIBUTES

=head2 targets

A L<Hash::Ordered> of the targets, in the order encountered.

=head1 FUNCTIONS

=cut

# }}}1

=head2 visit_goal

Add a target corresponding to the name of the goal.

=cut

sub visit_goal {
    my $self = shift or croak 'Need an instance';
    my $goal = shift or croak 'Need a goal';
    $self->targets->set($goal->name, $goal);
} #visit_goal()

#=head2 visit_node
#
#TODO
#
#=cut
#
#sub visit_node {
#    my $self = shift or croak 'Need an instance';
#    ...
#} #visit_node()

=head2 finalize

Write out the Makefile.

=cut

sub finalize {
    my ($self, %args) = parameters('self', [qw(phase dag data)], @_);
    hlog { Finalizing => __PACKAGE__ , '- phase', $args{phase} };
    return unless is_last_phase $args{phase};

    # During the Gen phase, create the Makefile
    open my $fh, '>', $self->dest_dir->file('Makefile') or die "Couldn't create Makefile";
    print $fh <<EOT;
# Makefile generated by hopen (https://github.com/cxw42/hopen)
# at @{[scalar gmtime]} GMT
# From ``@{[$self->proj_dir->absolute]}'' into ``@{[$self->dest_dir->absolute]}''

EOT

    my $iter = $self->targets->iterator;
    # TODO make this more robust and flexible
    while( my ($name, $goal) = $iter->() ) {
        hlog { __PACKAGE__, 'goal', $name, Dumper($goal) } 2;
        unless(eval { scalar @{$goal->outputs->{work}} }) {
            warn "No work for goal $name" unless $QUIET;
            next;
        }

        my @work = @{$goal->outputs->{work}};
        unshift @work, { to => $name, from => [$work[0]->{to}], how => undef };
            # Make a fake record for the goal.  TODO move this to visit_goal?

        foreach my $item (@work) {
            say $fh $item->{to}, ': ', join(' ', @{$item->{from}});
            say $fh (_expand($item) =~ s/^/\t/gmr);
            say $fh '';
        }

        say $fh "$name:";
        say $fh "\techo \"$name\"";
        say $fh '';
    }
    close $fh;
} #finalize()

=head2 default_toolset

Returns the package name of the default toolset for this generator,
which is C<Gnu> (i.e., L<Build::Hopen::T::Gnu>).

=cut

sub default_toolset { 'Gnu' }

=head1 INTERNALS

=head2 _expand

Produce the command line or lines associated with a work item.  Used by
L</finalize>.

=cut

sub _expand {
    my $item = shift or croak 'Need a work item';
    hlog { __PACKAGE__ . '::expand()', Dumper($item) } 2;
    my $out = $item->{how} or return '';    # no `how` => no output; not an error

    $out =~ s{#first\b}{$item->{from}->[0] // ''}ge;          # first input
    $out =~ s{#all\b}{join(' ', @{$item->{from}})}ge;   # all inputs
    $out =~ s{#out\b}{$item->{to}}ge;

    return $out;
} #_expand()

1;
__END__
# vi: set fdm=marker: #
