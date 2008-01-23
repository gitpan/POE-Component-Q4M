# $Id: /mirror/perl/POE-Component-Q4M/trunk/lib/POE/Component/Q4M.pm 39722 2008-01-23T00:28:27.355696Z daisuke  $
#
# Copyright (c) 2008 Daisuke Maki <daisuke@endeworks.jp>
# All rights reserved.

package POE::Component::Q4M;
use strict;
use warnings;
use base qw(Class::Accessor::Fast);
use POE qw(Component::EasyDBI);
use UNIVERSAL::require;
use constant DEBUG => 0;
our $VERSION = '0.00002';

__PACKAGE__->mk_accessors($_) for qw(alias connect_info database table sql_maker backend);

sub spawn
{
    my $class = shift;
    my %args  = @_;

    my $alias = $args{alias} || join('-', 'Q4m', $$, rand(), time());
    my $connect_info = $args{connect_info} || die "no connect_info specified";
    my $table = $args{table} || die "No table specified";

    my $sql_maker_class = $args{sql_maker_class} || 'SQL::Abstract';
    $sql_maker_class->require or die;
    my $sql_maker = $sql_maker_class->new();
    
    # XXX This is a hack. Hopefully it will be fixed in q4m
    $connect_info->[0] =~ /(?:dbname|database)=([^;]+)/;
    my $database = $1;

    my $dbi_session = POE::Component::EasyDBI->spawn(
        dsn      => $connect_info->[0],
        username => $connect_info->[1],
        password => $connect_info->[2],
        options  => $connect_info->[3] || {},
    );

    my $self = $class->SUPER::new({
        alias     => $alias,
        backend   => $dbi_session->ID,
        table     => $table,
        database  => $database,
        sql_maker => $sql_maker,
    });

    POE::Session->create(
        object_states => [
            $self => {
                _start => '_poe_start',
                _stop  => '_poe_stop',
                map { ($_ => "_poe_$_") }
                    qw(next insert insert_done fetchrow_hashref)
            }
        ]
    );
}

sub _poe_start
{
    my ($self, $kernel) = @_[OBJECT, KERNEL];

    DEBUG and warn "Starting " . $self->alias;
    $kernel->alias_set($self->alias) if $self->alias;
}

sub _poe_stop
{
    my ($self, $kernel) = @_[OBJECT, KERNEL];

    DEBUG and warn "Stopping " . $self->alias;
    $kernel->alias_remove( $self->alias ) if $self->alias;
}

sub _poe_insert
{
    my ($self, $kernel, $fieldvals) = @_[OBJECT, KERNEL, ARG0];

    my($stmt, @binds) = $self->sql_maker->insert( $self->table,  $fieldvals );
    $kernel->post($self->backend,
        insert => {
            sql => $stmt,
            placeholders => \@binds,
            event => 'insert_done',
        }
    ) or die;
}

sub _poe_insert_done
{
    DEBUG and warn "Inserted new item";
}

sub _poe_next
{
    my ($self, $kernel, $session, $ref, $heap) = @_[OBJECT, KERNEL, SESSION, ARG0, HEAP];

    if ($heap->{next_pending}) {
        return;
    }

    $heap->{next_pending}++;

    $ref->{sender} = $_[SENDER]->ID;
    my $postback = $session->postback(
        $ref->{method} || 'fetchrow_hashref',
        $ref
    );
    my $full_table = join('.', $self->database, $self->table);
    $kernel->post($self->backend,
        do => {
            sql          => qq|SELECT queue_wait("$full_table")|,
            event        => $postback,
        }
    ) or die;
}

sub _poe_fetchrow_hashref
{
    my ($self, $kernel, $pack, $heap) = @_[OBJECT, KERNEL, ARG0, HEAP];

    $heap->{next_pending}--;
    my $ref = $pack->[0];
    my ($stmt, @binds) = $self->sql_maker->select(
        $self->table,
        $ref->{fields},
    );

    my %hashargs = (
        %$ref,
        sql => $stmt,
    );
    $kernel->post($self->backend,
        hash => \%hashargs
    ) or die "failed to post to 'hash'";
}

1;

__END__

=head1 NAME

POE::Component::Q4M - Access Q4M From POE

=head1 SYNOPSIS

  POE::Session->create(
    inline_states => {
      _start => sub {
        POE::Component::Q4M->spawn(
          alias => 'Q4m',
          table => 'q4m',
          connect_info => [ ... ],
        );
        $_[KERNEL]->post('Q4M', 'next', {
          event   => 'got_message',
          method  => 'fetchrow_hashref',
          fields  => [ qw(col1 col2 col3) ]
        });
      }
      got_message => sub {
        my $h = $_[ARG0];
        print $h->{col1}, "\n";
      }
    }
  );

=head1 DESCRIPTION

POE::Component::Q4M is a simple POE wrapper around Q4M.

=head1 METHODS

=head2 spawn

  POE::Component::Q4M->spawn(
    alias        => $alias, # default Q4M
    table        => $table, # required
    connect_info => \@connet_info, # required
  );

Creates a new Q4M session.

=head1 STATES

=head2 next

  $kernel->post(Q4M => 'next', {
    event => $event, # name or ID of event to receive response
    session => $session, # default $_[SENDER]
    method => 'fetchrow_hashref',
    fields => [ qw(col1 col2 col3) ]
  });

Grabs the next row, and passes the result to 'event'

=head1 TODO

Need to implment "insert".

Not sure if we want to pass the results from the backend directly to the
final event

Error handling.

=head1 AUTHOR

Copyright (c) 2008 Daisuke Maki E<lt>daisuke@endeworks.jpE<gt>

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

See http://www.perl.com/perl/misc/Artistic.html

=cut