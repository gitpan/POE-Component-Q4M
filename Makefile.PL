use strict;
use inc::Module::Install;

name('POE-Component-Q4M');
all_from('lib/POE/Component/Q4M.pm');

requires 'POE';
requires 'POE::Component::EasyDBI';

auto_install;
WriteAll;