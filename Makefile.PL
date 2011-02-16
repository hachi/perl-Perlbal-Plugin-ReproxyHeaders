#!/usr/bin/perl

use inc::Module::Install;

name        'Perlbal-Plugin-ReproxyHeaders';
all_from    'lib/Perlbal/Plugin/ReproxyHeaders.pm';

requires    'Perlbal'   => 0;

WriteAll;
