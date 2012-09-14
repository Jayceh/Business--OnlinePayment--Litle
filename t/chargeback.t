#!/usr/bin/perl -w

use Test::More qw(no_plan);
use Data::Dumper; 
## grab info from the ENV
my $login = $ENV{'BOP_USERNAME'} ? $ENV{'BOP_USERNAME'} : 'TESTMERCHANT';
my $password = $ENV{'BOP_PASSWORD'} ? $ENV{'BOP_PASSWORD'} : 'TESTPASS';
my $merchantid = $ENV{'BOP_MERCHANTID'} ? $ENV{'BOP_MERCHANTID'} : 'TESTMERCHANTID';
my $date = $ENV{'BOP_ACTIVITYDATE'} ? $ENV{'BOP_ACTIVITYDATE'} : '2012-09-13';

my @opts = ('default_Origin' => 'RECURRING');

my $str = do { local $/ = undef; <DATA> };
my $data;
eval($str);

my $authed = 
    $ENV{BOP_USERNAME}
    && $ENV{BOP_PASSWORD}
    && $ENV{BOP_MERCHANTID};

use_ok 'Business::OnlinePayment';

SKIP: {
    skip "No Auth Supplied", 3 if ! $authed;
    ok( $login, 'Supplied a Login' );
    ok( $password, 'Supplied a Password' );
    like( $merchantid, qr/^\d+/, 'Supplied a MerchantID');
}

my %orig_content = (
    login => $login,
    password => $password,
    merchantid => $merchantid,
);

my $chargeback_activity;
my $tx = Business::OnlinePayment->new("Litle", @opts);
$tx->test_transaction(1);

SKIP: {
    skip "No Test Account setup",17 if ! $authed;
    ### list test
    print '-'x70;
    print "CHARGEBACK ACTIVITY TESTS\n";
    my %content = %orig_content;
    $content{'activity_date'} = $date;
    $tx->content(%content);
    $chargeback_activity = $tx->chargeback_activity_request();
    is( $tx->is_success, 1, "Chargeback activity request" );
    my $cnt = scalar(@{$chargeback_activity});
    is( $cnt > 0, 1, "Objectified all test cases" );
    if ( $tx->is_success && $cnt == 0 && ! defined $ENV{'BOP_ACTIVITYDATE'} ) {
        diag('-'x70);
        diag('$ENV{\'BOP_ACTIVITYDATE\'} not set, this probably caused your last test to fail.');
        diag('-'x70);
    }

    foreach my $resp ( @{ $chargeback_activity } ) {
        my ($resp_validation) = grep { $merchantid == $resp->merchant_id && $_->{'id'} == $resp->case_id } @{ $data->{'activity_response'} };
        response_check(
            $resp,
            desc => 'List Response Check',
            reason_code => $resp_validation->{'reasonCode'},
            reason_code_description => $resp_validation->{'reasonCodeDescription'},
            type => $resp_validation->{'chargebackType'},
        );
    }
}

SKIP: {
    skip "No Test Account setup",4 if ! $authed;
    my ($merchant_automated) = grep { $_->{'currentQueue'} eq 'Merchant Automated' } @{ $chargeback_activity };
    is( defined $merchant_automated, 1, "Chargeback currentQueue = 'Merchant Automated' caseid found" );

    skip "No caseid's have currentQueue = 'Merchant Automated'",3 if ! defined $merchant_automated;

    my %content = %orig_content;
    $content{'case_id'} = $merchant_automated->case_id;
    $content{'merchant_activity_id'} = time();
    $content{'activity'} = 'Assign To Merchant';

    $tx->content(%content);
    $tx->chargeback_update_request();
    is( $tx->is_success, 1, "Chargeback caseid update: " . $content{'case_id'} );
    is( $tx->result_code, '0', "result_code(): RESULT" );
    is( $tx->error_message, 'Valid Format', "error_message(): RESULT" );
}

foreach $filePTR ( @{ $data->{'test_images'} } ) {
    open FILE, 't/resources/'.$filePTR->{'filename'} or die $!;
    binmode FILE;
    my $buf;
    while ( (read FILE, $buf, 4096) != 0) {
        $filePTR->{'filecontent'} .= $buf;
    }
    close(FILE);
    ok( length($filePTR->{'filecontent'}) > 1000, "Loaded from disk: ".$filePTR->{'filename'} );
}

my $chargeback_list = {};
my $caseid = 0;
SKIP: {
    skip "No Test Account setup",6 if ! $authed;
    my ($resp_validation) = grep { $_->{'currentQueue'} eq 'Merchant' } @{ $chargeback_activity };
    if (defined $resp_validation && $resp_validation->case_id) { $caseid = $resp_validation->case_id; }
    is( $caseid > 0, 1, "Caseid found: " . $caseid );
}

SKIP: {
    skip "No Test Account setup",6 if ! $authed;
    skip "No caseid found",6 if $caseid == 0;
    my %content = %orig_content;
    $content{'case_id'} = $caseid;

    foreach $filePTR ( @{ $data->{'test_images'} } ) {
        $content{'filename'} = $filePTR->{'filename'};
        $content{'filecontent'} = $filePTR->{'filecontent'};
        $content{'mimetype'} = $filePTR->{'mimetype'};
        $tx->content(%content);
        $chargeback_list = $tx->chargeback_upload_support_doc();
        is( $tx->is_success, 1, "Chargeback upload: " . $content{'filename'} );
        is( $tx->result_code, '000', "result_code(): RESULT" );
        is( $tx->error_message, 'Success', "error_message(): RESULT" );
        if ($tx->result_code eq '005') {
            diag('-'x70);
            diag('Result code 005 means that someone probably aborted the last test sequence early');
            diag('-'x70);
        }
    }
}

SKIP: {
    skip "No Test Account setup",6 if ! $authed;
    skip "No caseid found",6 if $caseid == 0;
    my %content = %orig_content;
    $content{'case_id'} = $caseid;
    $tx->content(%content);
    $chargeback_list = $tx->chargeback_list_support_docs();
    is( $tx->is_success, 1, "Chargeback list request" );
    my $cnt = scalar(keys %{$chargeback_list});
    is( $cnt >= 1, 1, "Chargeback list found $cnt files" );
    is( $tx->result_code, '000', "result_code(): RESULT" );
    is( $tx->error_message, 'Success', "error_message(): RESULT" );

    foreach my $filename ( keys %{ $chargeback_list } ) {
        my ($resp_validation) = grep { $_->{'filename'} eq $filename } @{ $data->{'list_response'} };
        is ( $filename, $resp_validation->{'filename'}, "Chargeback list found filename: " . $filename );
    }
}

SKIP: {
    skip "No Test Account setup",6 if ! $authed;
    skip "No caseid found",6 if $caseid == 0;
    my %content = %orig_content;
    $content{'case_id'} = $caseid;

    foreach $filePTR ( @{ $data->{'test_images'} } ) {
        $content{'filename'} = $filePTR->{'filename'};
        $content{'filecontent'} = $filePTR->{'filecontent'};
        $content{'mimetype'} = $filePTR->{'mimetype'};
        $tx->content(%content);
        $chargeback_list = $tx->chargeback_replace_support_doc();
        is( $tx->is_success, 1, "Chargeback replace: " . $content{'filename'} );
        is( $tx->result_code, '000', "result_code(): RESULT" );
        is( $tx->error_message, 'Success', "error_message(): RESULT" );
    }
}

SKIP: {
    skip "No Test Account setup",6 if ! $authed;
    skip "No caseid found",6 if $caseid == 0;
    my %content = %orig_content;
    $content{'case_id'} = $caseid;

    foreach $filePTR ( @{ $data->{'test_images'} } ) {
        $content{'filename'} = $filePTR->{'filename'};
        $tx->content(%content);
        $chargeback_list = $tx->chargeback_retrieve_support_doc();
        is( $tx->is_success, 1, "Chargeback retrieve: " . $content{'filename'} );
        is( $tx->result_code, '000', "result_code(): RESULT" );
        is( $tx->error_message, 'Success', "error_message(): RESULT" );
    }
}

SKIP: {
    skip "No Test Account setup",6 if ! $authed;
    skip "No caseid found",6 if $caseid == 0;
    my %content = %orig_content;
    $content{'case_id'} = $caseid;
    # Note the delete test must run, or it will make the next "upload" test sequence fail

    foreach $filePTR ( @{ $data->{'test_images'} } ) {
        $content{'filename'} = $filePTR->{'filename'};
        $tx->content(%content);
        $chargeback_list = $tx->chargeback_delete_support_doc();
        is( $tx->is_success, 1, "Chargeback delete: " . $content{'filename'} );
        is( $tx->result_code, '000', "result_code(): RESULT" );
        is( $tx->error_message, 'Success', "error_message(): RESULT" );
    }
}

#-----------------------------------------------------------------------------------
#
sub tx_check {
    my $tx = shift;
    my %o = @_;

    is( $tx->is_success, $o{is_success}, "$o{desc}: " . tx_info($tx) );
    is( $tx->result_code, $o{result_code}, "result_code(): RESULT" );
    is( $tx->error_message, $o{error_message}, "error_message() / RESPMSG" );
    if( $o{authorization} ){
        is( $tx->authorization, $o{authorization}, "authorization() / AUTHCODE" );
    }
    if( $o{avs_code} ){
        is( $tx->avs_code, $o{avs_code}, "avs_code() / AVSADDR and AVSZIP" );
    }
    if( $o{cvv2_response} ){
        is( $tx->cvv2_response, $o{cvv2_response}, "cvv2_response() / CVV2MATCH" );
    }
    like( $tx->order_number, qr/^\w{5,19}/, "order_number() / PNREF" );
}

#
sub response_check {
    my $tx = shift;
    my %o = @_;

    is( $tx->reason_code, $o{reason_code}, "reason_code(): RESULT" );
    is( $tx->reason_code_description, $o{reason_code_description}, "reason_code_description(): RESULT" );
    is( $tx->hash->{'chargebackType'}, $o{type}, "type() / RESPMSG" );
}
sub tx_info {
    my $tx = shift;

    no warnings 'uninitialized';

    return (
        join( "",
            "is_success(", $tx->is_success, ")",
            " order_number(", $tx->order_number, ")",
            " error_message(", $tx->error_message, ")",
            " result_code(", $tx->result_code, ")",
            " invoice_number(", $tx->invoice_number , ")",
        )
    );
}

sub expiration_date {
    my($month, $year) = (localtime)[4,5];
    $year++; # So we expire next year.
    $year %= 100; # y2k? What's that?

    return sprintf("%02d%02d", $month, $year);
}

__DATA__
$data= {
'list_response' => [
    {
        'filename' => 'testImage.jpg',
    },
    {
        'filename' => 'testImage2.jpg',
    },
],
'test_images' => [
    {
        'filename' => 'testImage.jpg',
        'mimetype' => 'image/jpeg',
    },
    {
        'filename' => 'testImage2.jpg',
        'mimetype' => 'image/jpeg',
    },
],
'activity_response' => [
    {
        id => '60700001',
        'chargebackType' => 'Deposit',
        'reasonCodeDescription' => 'Contact Litle & Co for Definition',
        'reasonCode' => '00A1',
    },
{
    id => '60700002',
    'fromQueue' => 'Merchant',
    'chargebackType' => 'Deposit',
    'reasonCodeDescription' => 'Contact Litle & Co for Definition',
    'reasonCode' => '00A1',
},
  {
    id => '60700003',
    'chargebackType' => 'Deposit',
    'reasonCodeDescription' => 'Contact Litle & Co for Definition',
    'reasonCode' => '00A1',
  },
  {
    id => '60700004',
    'fromQueue' => 'Merchant',
    'chargebackType' => 'Deposit',
    'reasonCodeDescription' => 'Contact Litle & Co for Definition',
    'reasonCode' => '00A1',
  },
  ],
        };
