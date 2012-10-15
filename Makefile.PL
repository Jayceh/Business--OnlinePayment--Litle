use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Business::OnlinePayment::Litle',
    AUTHOR              => q{Jason Hall <jayce@lug-nut.com>},
    VERSION_FROM        => 'Litle.pm',
    ABSTRACT_FROM       => 'Litle.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'Business::OnlinePayment'        => 0,
        'Business::OnlinePayment::HTTPS' => 0,
        'XML::Writer'          => 0,
        'XML::Simple'          => 0,
        'Tie::IxHash'          => 0,
        'Business::CreditCard' => 0,
        'Net::SSLeay'          => 0,
        'Net::SFTP::Foreign'   => '1.57',
        'IO::String'           => 0,
        'HTTP::Tiny'           => '0.022',
        'Log::Scrubber'        => '0.11',
        'IO::Socket::SSL'      => '1.56', # required by HTTP::Tiny for SSL to work
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Business-OnlinePayment-Litle-*' },
);
