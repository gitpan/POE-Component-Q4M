use strict;
use Test::More (skip_all => "maybe later");
use POE qw(Component::Q4M);

if (0) {
POE::Session->create(
    inline_states => {
        _start => sub {
            POE::Component::Q4M->spawn(
                alias => 'Q4M',
                table => 'q4m_t',
                connect_info => [
                    'dbi:mysql:dbname=test',
                    'root',
                    '',
                    {}
                ]
            );

            $_[KERNEL]->post(Q4M => 'next', { event => 'got_message' });
        },
        got_message => sub {
            $_[KERNEL]->post(Q4M => 'next', { event => 'got_message' });
            
        }
    }
);

POE::Kernel->run;
}