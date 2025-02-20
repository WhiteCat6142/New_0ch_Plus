#============================================================================================================
#
#	汎用データ変換・取得モジュール
#
#============================================================================================================
package	DATA_UTILS;

use strict;
use utf8;
use open IO => ':encoding(cp932)';
use warnings;
use Encode;
no warnings qw(once);

#------------------------------------------------------------------------------------------------------------
#
#	モジュールコンストラクタ - new
#	-------------------------------------------
#	引　数：なし
#	戻り値：モジュールオブジェクト
#
#------------------------------------------------------------------------------------------------------------
sub new
{
	my $class = shift;
	
	my $obj = {};
	bless $obj, $class;
	
	return $obj;
}

#------------------------------------------------------------------------------------------------------------
#
#	URL引数取得 - GetArgument
#	-------------------------------------------
#	引　数：$pENV : %ENVのリファレンス
#	戻り値：引数配列
#
#------------------------------------------------------------------------------------------------------------
sub GetArgument
{
	my $this = shift;
	my ($pENV) = @_;
	
	my @retArg = ();
	
	# PATH_INFOあり
	if (defined $pENV->{'PATH_INFO'} && $pENV->{'PATH_INFO'} ne '') {
		my @Awork = split(/\//, $pENV->{'PATH_INFO'}, -1);
		@retArg = (@Awork[1, 2], ConvertOption($Awork[3]));
	}
	# QUERY_STRING
	else {
		my @Awork = split(/[&;]/, $pENV->{'QUERY_STRING'}, -1);
		@retArg = (undef, undef, 0, 1, 1000, 1, 0);
		foreach (@Awork) {
			my ($var, $val) = split(/=/, $_, 2);
			$retArg[0] = $val if ($var eq 'bbs');	# BBS
			$retArg[1] = $val if ($var eq 'key');	# スレッドキー
			$retArg[3] = $val if ($var eq 'st');	# 開始レス番
			$retArg[4] = $val if ($var eq 'to');	# 終了レス番
			# 1非表示
			if ($var eq 'nofirst' && $val eq 'true') {
				$retArg[5] = 1;
			}
			# 最新n件表示
			if ($var eq 'last' && $val != -1) {
				$retArg[2] = 1;
				$retArg[3] = $val;
				$retArg[4] = $val;
			}
		}
		# 単独表示フラグ
		if ($retArg[3] == $retArg[4] && $retArg[2] != 1) {
			$retArg[6] = 1;
		}
	}
	
	return @retArg;
}

#------------------------------------------------------------------------------------------------------------
#
#	表示レス数正規化 - RegularDispNum
#	-------------------------------------------
#	引　数：$Sys   : SYSTEM
#			$Dat   : DATオブジェクト
#			$last  : lastフラグ
#			$start : 開始行
#			$end   : 終了行
#	戻り値：(開始行、終了行)
#
#------------------------------------------------------------------------------------------------------------
sub RegularDispNum
{
	my $this = shift;
	my ($Sys, $Dat, $last, $start, $end) = @_;
	
	# 大きさ判定 swap
	if ($start > $end && $end != -1) {
		($start, $end) = ($end, $start);
	}
	
	my $resmax = $Dat->Size();
	my ($st, $ed);
	
	# 最新n件表示
	if ($last == 1) {
		$st = $resmax - $start + 1;
		$st = 1 if ($st < 1);
		$ed = $resmax;
	}
	# 指定表示
	elsif ($start || $end) {
		if ($end == -1) {
			$st = $start < 1 ? 1 : $start;
			$ed = $resmax;
		}
		else {
			$st = $start < 1 ? 1 : $start;
			$ed = $end < $resmax ? $end : $resmax;
		}
	}
	# 全件表示
	else {
		$st = 1;
		$ed = $resmax;
	}
	
	# 時間による制限有り
	if ($Sys->Get('LIMTIME')) {
		# 表示レス数が100超えた
		if ($ed - $st >= 100) {
			$ed = $st + 100 - 1;
		}
	}
	return ($st, $ed);
}

#------------------------------------------------------------------------------------------------------------
#
#	URL変換 - ConvertURL
#	--------------------------------------------
#	引　数：$Sys : SYSTEMモジュール
#			$Set : SETTING
#			$mode : エージェント
#			$text : 変換テキスト(リファレンス)
#	戻り値：変換後のメッセージ
#
#------------------------------------------------------------------------------------------------------------
sub ConvertURL
{
	my $this = shift;
	my ($Sys, $Set, $mode, $text) = @_;
	
	# 時間による制限有り
	return $text if ($Sys->Get('LIMTIME'));
	
	my $server = $Sys->Get('SERVER');
	my $cushion = $Set->Get('BBS_REFERER_CUSHION');
	my $reg1 = q{(?<!a href=")(?<!src=")(https?|ftp)://(([-\w.!~*';/?:\@=+\$,%#]|&(?![lg]t;))+)};	# URL検索１
	my $reg2 = q{<(?<!a href=")(?<!src=")(https?|ftp)::(([-\w.!~*';/?:\@=+\$,%#]|&(?![lg]t;))+)>};	# URL検索２
	
	# 携帯から
	if ($mode eq 'O') {
		$$text =~ s/$reg1/<$1::$2>/g;
		while ($$text =~ /$reg2/) {
			my $work = (split(/\//, $2))[0];
			$work =~ s/(www\.|\.com|\.net|\.jp|\.co|\.ne)//g;
			$$text =~ s|$reg2|<a href="$1://$2">$work</a>|;
		}
		$$text =~ s/ <br> /<br>/g;
		$$text =~ s/\s*<br>/<br>/g;
		$$text =~ s/(?:<br>){2}/<br>/g;
		$$text =~ s/(?:<br>){3,}/<br><br>/g;
	}
	# PCから
	else {
		# クッションあり
		if ($cushion) {
			$server =~ /$reg1/;
			$server = $2;
			$$text =~ s/$reg1/<$1::$2>/g;
			while ($$text =~ /$reg2/) {
				# 自鯖リンク -> クッションなし
				if ($2 =~ m{^\Q$server\E(?:/|$)}) {
					$$text =~ s|$reg2|<a href="$1://$2" target="_blank">$1://$2</a>|;
				}
				# 自鯖以外
				else {
					if($1 eq 'http') {
						$$text =~ s|$reg2|<a href="$1://$cushion$2" target="_blank">$1://$2</a>|;
					}
					elsif ($cushion =~ m{^(?:jump\.x0\.to|nun\.nu)/$}) {
						$$text =~ s|$reg2|<a href="http://$cushion$1://$2" target="_blank">$1://$2</a>|;
					}
					else {
						$$text =~ s|$reg2|<a href="$1://$2" target="_blank">$1://$2</a>|;
					}
				}
			}
		}
		# クッション無し
		else {
			$$text =~ s|$reg1|<a href="$1://$2" target="_blank">$1://$2</a>|g;
		}
	}
	return $text;
}
#Imgur埋め込み
sub ConvertImgur
{
	my $this = shift;
	my ($text) = @_ ;
	
	my $reg = '(?<!src=")(https://i\.imgur\.com/[A-Za-z0-9_]+\.(bmp|png|jpe?g))';	 # ImgurURL検索
	
	$$text =~ s|$reg|<blockquote class="imgur-embed-pub" lang="ja" data-id="a/$2"><a href="$1"></a></blockquote>|g;
	
	return $text;
	
}
=pod
sub ConvertVideo
{
	my $this = shift;
	my ($text) = @_;
	my $reg = q{(?<!src=")(?<!a href=")(https?:\/\/.*?\.mp4)};
	$$text =~ s||<video src="$1" width=100 height=100 controls preload="metadata">|g;
	
	return $text;
}
=cut
#Tweet埋め込み
sub ConvertTweet
{
	my $this = shift;
	my ($text) = @_ ;
	
	my $reg = '(?<!src=")(?<!a href=")(https://(twitter|x)\.com/[A-Za-z0-9_]+/status/([^\p{Hiragana}\p{Katakana}\p{Han}\s]+)/?)';	 # TwitterURL検索
	
	$$text =~ s|$reg|<a href="$1">$1</a><br><blockquote  class="twitter-tweet" data-width="300"><a href="$1">Tweet読み込み中...</a></blockquote>|g;
	
	return $text;
	
}
#つべニコ動埋め込み
sub ConvertMovie
{
    my $this = shift;
    my ($text) = @_ ;

    # Youtube URL patterns
    my $youtube_pattern1 = qr{(https://youtu\.be/([a-zA-Z0-9_-]+))};
    my $youtube_pattern2 = qr{(https://(www\.)?youtube\.com/watch\?v=([a-zA-Z0-9_-]+))};

    # NicoNico URL patterns
    my $nico_pattern1 = qr{(https://nico\.ms/sm([0-9]+))};
    my $nico_pattern2 = qr{(https://(www\.)?nicovideo\.jp/watch/sm([0-9]+))};

	my $reg1 = '<div class="video"><div class="video_iframe"><iframe width="560" height="315" src=';
	my $reg2 = 'frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"></iframe></div></div>';

    $$text =~ s|$youtube_pattern1|$reg1"https://www.youtube.com/embed/$2"$reg2|g;
    $$text =~ s|$youtube_pattern2|$reg1"https://www.youtube.com/embed/$3"$reg2|g;
    $$text =~ s|$nico_pattern1|$reg1"https://embed.nicovideo.jp/watch/sm$3"$reg2|g;
	$$text =~ s|$nico_pattern2|$reg1"https://embed.nicovideo.jp/watch/sm$3"$reg2|g;

    return $text;
}

#------------------------------------------------------------------------------------------------------------
#
#	引用変換 - ConvertQuotation
#	--------------------------------------------
#	引　数：$Sys : SYSTEMオブジェクト
#			$text : 変換テキスト
#			$mode : エージェント
#	戻り値：変換後のメッセージ
#
#------------------------------------------------------------------------------------------------------------
sub ConvertQuotation
{
	my $this = shift;
	my ($Sys, $text, $mode) = @_;
	
	# 時間による制限有り
	return $text if ($Sys->Get('LIMTIME'));
	
	my $pathCGI = $Sys->Get('SERVER') . $Sys->Get('CGIPATH');
	
	if ($Sys->Get('PATHKIND')) {
		# URLベースを生成
		my $buf = '<a class=reply_link href="';
		$buf .= $pathCGI .  '/read.cgi';
		$buf .= '?bbs=' . $Sys->Get('BBS') . '&key=' . $Sys->Get('KEY');
		$buf .= '&nofirst=true';
		
		$$text =~ s{&gt;&gt;([1-9][0-9]*)-([1-9][0-9]*)}
					{$buf&st=$1&to=$2" target="_blank">>>$1-$2</a>}g;
		$$text =~ s{&gt;&gt;([1-9][0-9]*)-(?!0)}
					{$buf&st=$1&to=-1" target="_blank">>>$1-</a>}g;
		$$text =~ s{&gt;&gt;-([1-9][0-9]*)}
					{$buf&st=1&to=$1" target="_blank">>>$1-</a>}g;
		$$text =~ s{&gt;&gt;([1-9][0-9]*)}
					{$buf&st=$1&to=$1" target="_blank">>>$1</a>}g;
	}
	else{
		# URLベースを生成
		my $buf = "<a class=reply_link href=\"";
		$buf .= $pathCGI . '/read.cgi/';
		$buf .= $Sys->Get('BBS') . '/' . $Sys->Get('KEY');
		
		$$text =~ s{&gt;&gt;([1-9][0-9]*)-([1-9][0-9]*)}
					{$buf/$1-$2n" target="_blank">>>$1-$2</a>}g;
		$$text =~ s{&gt;&gt;([1-9][0-9]*)-(?!0)}
					{$buf/$1-" target="_blank">>>$1-</a>}g;
		$$text =~ s{&gt;&gt;-([1-9][0-9]*)}
					{$buf/-$1" target="_blank">>>-$1</a>}g;
		$$text =~ s{&gt;&gt;([1-9][0-9]*)}
					{$buf/$1" target="_blank">>>$1</a>}g;
	}
	$$text	=~ s{>>(?=[1-9])}{&gt;&gt;}g;
	
	return $text;
}

#------------------------------------------------------------------------------------------------------------
#
#	特殊引用変換 - ConvertSpecialQuotation
#	--------------------------------------------
#	引　数：$Sys	SYSTEM
#           $text : 変換テキスト
#	戻り値：変換後のメッセージ
#
#------------------------------------------------------------------------------------------------------------
sub ConvertSpecialQuotation
{
	my $this = shift;
	my	($Sys, $text) = @_;
	
	$$text = '<br>' . $$text . '<br>';
	
	# ＞引用変換
	while($$text =~ /<br> ＞(.*?)<br>/){
		$$text =~ s/<br> ＞(.*?)<br>/<br><font color=gray>＞$1<\/font><br>/;
	}
	# ＃引用変換
	while($$text =~ /<br> ＃(.*?)<br>/){
		$$text =~ s/<br> ＃(.*?)<br>/<br><font color=green>＃$1<\/font><br>/;
	}
	# #引用変換
	while($$text =~ /<br> #(.*?)<br>/){
		$$text =~ s/<br> #(.*?)<br>/<br><font color=green>#$1<\/font><br>/;
	}
	
	# 最初につけた<br>を取り外す
	$$text = substr($$text,4,length($$text) - 8);
	
	return $text;
}

#------------------------------------------------------------------------------------------------------------
#
#	スレタイ変換 - ConvertThreadTitle
#	--------------------------------------------
#	引　数：$Sys : SYSTEMモジュール
#			$text : 変換テキスト(リファレンス)
#	戻り値：変換後のメッセージ
#
#------------------------------------------------------------------------------------------------------------
sub ConvertThreadTitle
{
	my $this = shift;
	my ($Sys, $text) =@_;
	my $cache = {};
	my @bbsname;
	# サーバー名を取得 「http://example.jp」
	my $server = $Sys->Get('SERVER');
	# CGIのパス部分を取得 「/test」
	my $cgipath = $Sys->Get('CGIPATH');
	my $oldbbs = $Sys->Get('BBS');
	require './module/bbs_info.pl';
	my $info = BBS_INFO->new;
	$info->Load($Sys);
	
	$$text =~ s{(?<=\>)\Q$server$cgipath\E/read\.cgi/([0-9a-zA-Z_\-]+)/([0-9]+)/?([0-9\-]+)?/?}{
		my $title = (($oldbbs eq $1)?'':($1.'/')).GetThreadTitle($Sys, $cache, $1, $2).($3?" >>$3":'');
		(defined $title ? $title : $&)
	}ge;
	
	return $text;
	
}
sub GetThreadTitle
{
	my ($Sys, $cache, $bbs, $thread) = @_;
	
	my $Threads = $cache->{$bbs};
	
	if (!defined $cache->{$bbs}) {
		my $oldbbs = $Sys->Get('BBS');
		$Sys->Set('BBS', $bbs);
		
		require './module/thread.pl';
		$Threads = THREAD->new;
		$Threads->Load($Sys);
		$Threads->Close();
		$cache->{$bbs} = $Threads;
		
		$Sys->Set('BBS', $oldbbs);
	}
	
	my $title = $Threads->Get('SUBJECT', $thread);
	
	return $title;
}

#------------------------------------------------------------------------------------------------------------
#
#	汎用画像タグ変換
#	-------------------------------------------------------------------------------------
#	引数    	$Sys	SYSTEM
#	    	$limit	リンク時間制限
#	    	$text	対象文字列
#	戻り値	変換後のメッセージ
#
#------------------------------------------------------------------------------------------------------------
sub ConvertImageTag
{
	my $this = shift;
	my ($Sys,$limit, $text,$index) = @_;

	my $reg1 = q{(?<!src="?)https?://.*?\.(jpe?g|gif|bmp|png)};
	my $reg2 = q{<a.*?>(.*?\.(jpe?g|gif|bmp|png))};
	
	if($limit||($Sys->Get('URLLINK') eq 'FALSE')){
		if ($index){
			$$text =~ s|$reg1|<a href=\"$1\">$1</a><br><img class=\"post_image\" src=\"$1\" width=\"300px\" height=\"auto\">|g;
		}
		else{
			$$text =~ s|$reg1|<a href=\"$1\">$1</a><br><img class=\"post_image\" src=\"$1\" style=\"max-width:250px;height:auto;\">|g;
		}
	}
	else{
		if ($index){
			$$text =~ s|$reg2|<a href=\"$1\">$1</a><br><img class=\"post_image\" src=\"$1\" width=\"300px\" height=\"auto\">|g;
		}
		else{
			$$text =~ s|$reg2|<a href=\"$1\">$1</a><br><img sclass=\"post_image\" src=\"$1\" style=\"max-width:250px;height:auto;\">|g;
		}
	}
	return $text;
}
#------------------------------------------------------------------------------------------------------------
#
#	テキスト削除 - DeleteText
#	--------------------------------------------
#	引　数：$text : 対象テキスト(リファレンス)
#			$len  : 最大文字数
#	戻り値：成形後テキスト
#
#------------------------------------------------------------------------------------------------------------
sub DeleteText
{
	my $this = shift;
	my ($text, $len) = @_;
	
	my @lines = split(/ ?<br> ?/, $$text, -1);
	my $ret = '';
	my $tlen = 0;
	
	foreach (@lines) {
		$tlen += length $_;
		last if ($tlen > $len);
		$ret .= "$_<br>";
		$tlen += 4;
	}
	
	return substr($ret, 0, -4);
}

#------------------------------------------------------------------------------------------------------------
#
#	改行数取得 - GetTextLine
#	--------------------------------------------
#	引　数：$text : 対象テキスト(リファレンス)
#	戻り値：改行数
#
#------------------------------------------------------------------------------------------------------------
sub GetTextLine
{
	my $this = shift;
	my ($text) = @_;
	
	$_ = $$text;
	my $l = s/(\r\n|[\r\n])/a/g || s/(<br>)/a/gi;
	
	return ($l + 1);
}

#------------------------------------------------------------------------------------------------------------
#
#	行列情報取得 - GetTextInfo
#	------------------------------------------------
#	引　数：$text : 調査テキスト(リファレンス)
#	戻り値：($tline,$tcolumn) : テキストの行数と
#			テキストの最大桁数
#	備　考：テキストの行区切りは<br>になっていること
#
#------------------------------------------------------------------------------------------------------------
sub GetTextInfo
{
	my $this = shift;
	my ($text) = @_;
	
	my @lines = split(/ ?<br> ?/, $$text, -1);
	
	my $mx = 0;
	foreach (@lines) {
		if ($mx < length($_)) {
			$mx = length($_);
		}
	}
	
	return (scalar(@lines), $mx);
}

#------------------------------------------------------------------------------------------------------------
#
#	エージェントモード取得 - GetAgentMode
#	--------------------------------------------
#	引　数：$UA   : ユーザーエージェント
#	戻り値：エージェントモード
#
#------------------------------------------------------------------------------------------------------------
sub GetAgentMode
{
	my $this = shift;
	my ($client) = @_;
	
	my $agent = '0';
	
	if ($client & $ZP::C_MOBILEBROWSER) {
		$agent = 'O';
	}
	elsif ($client & $ZP::C_FULLBROWSER) {
		$agent = 'Q';
	}
	elsif ($client & $ZP::C_P2) {
		$agent = 'P';
	}
	elsif ($client & $ZP::C_IPHONE_F) {
		$agent = 'i';
	}
	elsif ($client & $ZP::C_IPHONEWIFI) {
		$agent = 'I';
	}
	else {
		$agent = '0';
	}
	
	return $agent;
}

#------------------------------------------------------------------------------------------------------------
#
#	クライアント(機種)取得 - GetClient
#	--------------------------------------------
#	引　数：なし
#	戻り値：クライアント(機種)
#
#------------------------------------------------------------------------------------------------------------
sub GetClient
{
	my $this = shift;
	
	my $ua = $ENV{'HTTP_USER_AGENT'} || '';
	my $host = $ENV{'REMOTE_HOST'};
	my $addr = ($ENV{HTTP_CF_CONNECTING_IP}) ? $ENV{HTTP_CF_CONNECTING_IP} : $ENV{REMOTE_ADDR};
	my $client = 0;
	
	require './module/cidr_list.pl';
	
	my $cidr = $ZP_CIDR::cidr;
	
	if (CIDRHIT($cidr->{'docomo'}, $addr)) {
		$client = $ZP::C_DOCOMO_M;
	}
	elsif (CIDRHIT($cidr->{'docomo_pc'}, $addr)) {
		$client = $ZP::C_DOCOMO_F;
	}
	elsif (CIDRHIT($cidr->{'vodafone'}, $addr)) {
		$client = $ZP::C_SOFTBANK_M;
	}
	elsif (CIDRHIT($cidr->{'vodafone_pc'}, $addr)) {
		$client = $ZP::C_SOFTBANK_F;
	}
	elsif (CIDRHIT($cidr->{'ezweb'}, $addr)) {
		$client = $ZP::C_AU_M;
	}
	elsif (CIDRHIT($cidr->{'ezweb_pc'}, $addr)) {
		$client = $ZP::C_AU_F;
	}
	elsif (CIDRHIT($cidr->{'emobile'}, $addr)) {
		if ($ua =~ m|^emobile/1\.0\.0|) {
			$client = $ZP::C_EMOBILE_M;
		}
		else {
			$client = $ZP::C_EMOBILE_F;
		}
	}
	elsif (CIDRHIT($cidr->{'willcom'}, $addr)) {
		if ($ua =~ m|^Mozilla/3\.0|) {
			$client = $ZP::C_WILLCOM_M;
		}
		elsif ($ua =~ m|^Mozilla/4\.0| && $ua =~ m/IEMobile|PPC/) {
			$client = $ZP::C_WILLCOM_M;
		}
		else {
			$client = $ZP::C_WILLCOM_F;
		}
	}
	elsif (CIDRHIT($cidr->{'ibis'}, $addr)) {
		$client = $ZP::C_IBIS;
	}
	elsif (CIDRHIT($cidr->{'jig'}, $addr)) {
		$client = $ZP::C_JIG;
	}
	elsif (CIDRHIT($cidr->{'iphone'}, $addr)) {
		$client = $ZP::C_IPHONE_F;
	}
	elsif (CIDRHIT($cidr->{'p2'}, $addr)) {
		$client = $ZP::C_P2;
	}
	elsif ($host =~ m|\.opera-mini\.net$|) {
		$client = $ZP::C_OPERAMINI;
	}
	elsif ($ua =~ / iPhone| iPad/) {
		$client = $ZP::C_IPHONEWIFI;
	}
	else {
		$client = $ZP::C_PC;
	}
	
	return $client;
}

#------------------------------------------------------------------------------------------------------------
#
#	IPチェック(CIDR対応) by (-Ac)
#	-------------------------------------------------------------------------------------
#	@param	$orz	CIDRリスト(配列)
#	@param	$ho		チェック文字
#	@return	ヒットした場合1 それ以外は0
#
#------------------------------------------------------------------------------------------------------------

sub CIDRHIT
{
	
	my ($orz, $ho) = @_;
	
	foreach (@$orz) {
		# 完全一致 = /32 ってことで^^;
		$_ .= '/32' if ($_ !~ m|/|);
		
		# 以下CIDR形式
		my ($target, $length) = split('/', $_);
		
		my $ipaddr = unpack("B$length", pack('C*', split(/\./, $ho)));
		$target = unpack("B$length", pack('C*', split(/\./, $target)));
		
		if ($target eq $ipaddr) {
			return 1;
		}
	}
	
	return 0;
}

#------------------------------------------------------------------------------------------------------------
#
#	携帯機種情報取得
#	-------------------------------------------------------------------------------------
#	@param	$client	
#	@return	個体識別番号
#
#------------------------------------------------------------------------------------------------------------
sub GetProductInfo
{
	my $this = shift;
	my ($client) = @_;
	
	my $product;
	
	# docomo
	if ( $client & $ZP::C_DOCOMO ) {
		# $ENV{'HTTP_X_DCMGUID'} - 端末製造番号, 個体識別情報, ユーザID, iモードID
		$product = $ENV{'HTTP_X_DCMGUID'};
		$product =~ s/^X-DCMGUID: ([a-zA-Z0-9]+)$/$1/i;
	}
	# SoftBank
	elsif ( $client & $ZP::C_SOFTBANK ) {
		# USERAGENTに含まれる15桁の数字 - 端末シリアル番号
		$product = $ENV{'HTTP_USER_AGENT'};
		$product =~ s/.+\/SN([A-Za-z0-9]+)\ .+/$1/;
	}
	# au
	elsif ( $client & $ZP::C_AU ) {
		# $ENV{'HTTP_X_UP_SUBNO'} - サブスクライバID, EZ番号
		$product = $ENV{'HTTP_X_UP_SUBNO'};
		$product =~ s/([A-Za-z0-9_]+).ezweb.ne.jp/$1/i;
	}
	# e-mobile(音声端末)
	elsif ( $client & $ZP::C_EMOBILE ) {
		# $ENV{'X-EM-UID'} - 
		$product = $ENV{'X-EM-UID'};
		$product =~ s/x-em-uid: (.+)/$1/i;
	}
	# 公式p2
	elsif ( $client & $ZP::C_P2 ) {
		# $ENV{'HTTP_X_P2_CLIENT_IP'} - (発言者のIP)
		# $ENV{'HTTP_X_P2_MOBILE_SERIAL_BBM'} - (発言者の固体識別番号)
		$ENV{'REMOTE_P2'} = ($ENV{HTTP_CF_CONNECTING_IP}) ? $ENV{HTTP_CF_CONNECTING_IP} : $ENV{REMOTE_ADDR};
		(($ENV{HTTP_CF_CONNECTING_IP}) ? $ENV{HTTP_CF_CONNECTING_IP} : $ENV{REMOTE_ADDR}) = $ENV{'HTTP_X_P2_CLIENT_IP'};
		$ENV{'REMOTE_HOST'} = $this->GetRemoteHost(($ENV{HTTP_CF_CONNECTING_IP}) ? $ENV{HTTP_CF_CONNECTING_IP} : $ENV{REMOTE_ADDR});
		if( $ENV{'HTTP_X_P2_MOBILE_SERIAL_BBM'} ne "" ) {
			$product = $ENV{'HTTP_X_P2_MOBILE_SERIAL_BBM'};
		}
		else {
			$product = $ENV{'HTTP_USER_AGENT'};
			$product =~ s/.+p2-user-hash: (.+)\)/$1/i;
		}
	}
	else {
		$product = $ENV{'REMOTE_HOST'};
	}
	
	return $product;
}

#------------------------------------------------------------------------------------------------------------
#
#	リモートホスト(IP)取得関数 - GetRemoteHost
#	---------------------------------------------
#	引　数：なし
#	戻り値：IP、リモホス
#
#------------------------------------------------------------------------------------------------------------
sub GetRemoteHost
{
	my $this = shift;
	
	my $host = ($ENV{HTTP_CF_CONNECTING_IP}) ? $ENV{HTTP_CF_CONNECTING_IP} : $ENV{REMOTE_ADDR};
	$host = gethostbyaddr(pack('C4', split(/\./, $host)), 2) || $host;
	
	return $host;
}

#------------------------------------------------------------------------------------------------------------
#
#	ID作成関数 - MakeID
#	--------------------------------------
#	引　数：$server : サーバー名
#			$client : 端末
#			$koyuu  : 端末固有識別子
#			$bbs    : 板名
#			$column : ID桁数
#	戻り値：ID
#
#------------------------------------------------------------------------------------------------------------
sub MakeID
{
	my $this = shift;
	my ($server, $client, $koyuu, $bbs, $column) = @_;
	
	# 種の生成
	my $uid;
	if ($client & ($ZP::C_P2 | $ZP::C_MOBILE)) {
		# 端末番号 もしくは p2-user-hash の上位3文字を取得
		#$uid = main::GetProductInfo($this, $ENV{'HTTP_USER_AGENT'}, $ENV{'REMOTE_HOST'});
		if (length($koyuu) > 8) {
			$uid = substr($koyuu, 0, 2) . substr($koyuu, -6, 3);
		}
		else {
			$uid = substr($koyuu, 0, 5);
		}
	}
	else {
		# IPを分解
		my @nums = split(/\./, (($ENV{HTTP_CF_CONNECTING_IP}) ? $ENV{HTTP_CF_CONNECTING_IP} : $ENV{REMOTE_ADDR}));
		# 上位3つの1桁目取得
		$uid = substr($nums[3], -2) . substr($nums[2], -2) . substr($nums[1], -1);
	}
	
	my @times = localtime time;
	
	# サーバー名・板名を結合する
	$uid .= substr(crypt($server, $times[4]), 2, 1) . substr(crypt($bbs, $times[4]), 2, 2);
	
	# 桁を設定
	$column *= -1;
	
	# IDの生成
	my $ret = substr(crypt(crypt($uid, $times[5]), $times[3] + 31), $column);
	$ret =~ s/\./+/g;
	
	return $ret;
}
sub MakeIDnew {
    my $this = shift;
    my ($Sys, $column,$Ninja) = @_;

    require './module/thread.pl';
    my $Threads = THREAD->new;
    $Threads->LoadAttr($Sys);

    # セッション情報を取得
    my $infoDir = $Sys->Get('INFO');
    my $ninDir = ".$infoDir/.nin/";
    my $Cookie = $Sys->Get('MainCGI')->{'COOKIE'};
    my $sid = $Cookie->Get('countsession');
	if ($sid eq '') {
		my %cookies = fetch CGI::Cookie;
		if (exists $cookies{'countsession'}) {
			$sid = $cookies{'countsession'}->value;
			$sid =~ s/"//g;
		}
	}

    # セッションが存在するか確認。初期値は0(not valid)。
    my $valid_session = 0;
    if ($sid) {
        my $user_session = CGI::Session->new('driver:file;serializer:default', $sid, { Directory => $ninDir }) || 0;
        if ($user_session) {
            $valid_session = 1;
        }
    }

    my $addr = $ENV{HTTP_CF_CONNECTING_IP} ? $ENV{HTTP_CF_CONNECTING_IP} : $ENV{REMOTE_ADDR};
    my @ip = split(/\./,$addr);
    my $ua = $ENV{'HTTP_SEC_CH_UA'} // $ENV{'HTTP_USER_AGENT'};

    my $provider;
    my $HOST = $ENV{'HTTP_HOST'};

	# プロバイダのドメインを取得
	if ($HOST) {
		$HOST =~ s/ne\.jp/nejp/g;
		$HOST =~ s/ad\.jp/adjp/g;
		$HOST =~ s/or\.jp/orjp/g;

		my @d = split(/\./, $HOST);  # リモートホストからドメイン部分を取り出す
		if (@d) {
			my $c = scalar @d;
			$provider = $d[$c - 2] . $d[$c - 1];
		}
	}

    require Digest::SHA::PurePerl;
    my $ctx = Digest::SHA::PurePerl->new;
    $ctx->add('0ch+ ID Generation');
    $ctx->add(':', $Sys->Get('SERVER'));
    $ctx->add(':', $Sys->Get('BBS'));
    # 正しいセッションが存在する場合はセッションIDを、存在しない場合はIPを使ってIDを生成
    if ($valid_session && $Ninja) {
        $ctx->add(':', $sid);
    } else {
        $ctx->add(':', $ip[0].$ip[1].$provider);
		$ctx->add(':', $ua);
    }
    $ctx->add(':', join('-', (localtime)[3,4,5]));
    $ctx->add(':', $Sys->Get('KEY')) if ($Threads->GetAttr($Sys->Get('KEY'),'changeid'));
    
    my $id = $ctx->b64digest;
    $id = substr($id, 0, $column);

    return $id;
}
#------------------------------------------------------------------------------------------------------------
#
#	トリップ作成関数 - ConvertTrip
#	--------------------------------------
#	引　数：$key     : トリップキー(リファレンス)
#			$column  : 桁数
#			$shatrip : 12桁トリップON/OFF
#	戻り値：変換後文字列
#
#------------------------------------------------------------------------------------------------------------
sub ConvertTrip
{
	my $this = shift;
	my ($key, $column, $shatrip) = @_;
	
	# cryptのときの桁取得
	$column *= -1;
	
	my $trip = '';
	$$key = '' if (!defined $$key);
	$$key = Encode::encode("cp932",$$key);
	if (length($$key) >= 12) {
		# 先頭1文字の取得
		my $mark = substr($$key, 0, 1);
		
		if ($mark eq '#' || $mark eq '$') {
			# 生キー
			if ($$key =~ m|^#([0-9a-zA-Z]{16})([./0-9A-Za-z]{0,2})$|) {
				my $key2 = pack('H*', $1);
				my $salt = substr($2 . '..', 0, 2);
				
				# 0x80問題再現
				$key2 =~ s/\x80[\x00-\xff]*$//;
				
				$trip = substr(crypt($key2, $salt), $column);
			}
			# 将来の拡張用
			else {
				$trip = '???';
			}
		}
		# SHA1(新仕様)トリップ
		elsif ($shatrip) {
			require Digest::SHA::PurePerl;
			Digest::SHA::PurePerl->import( qw(sha1_base64) );
			$trip = substr(sha1_base64($$key), 0, 12);
			$trip =~ tr/+/./;
		}
	}
	
	# 従来のトリップ生成方式
	if ($trip eq '') {
		my $salt = substr($$key, 1, 2);
		$salt = '' if (!defined $salt);
		$salt .= 'H.';
		$salt =~ s/[^\.-z]/\./go;
		$salt =~ tr/:;<=>?@[\\]^_`/ABCDEFGabcdef/;
		
		# 0x80問題再現
		$$key =~ s/\x80[\x00-\xff]*$//;
		
		$trip = substr(crypt($$key, $salt), $column);
	}
	
	return $trip;
}

#------------------------------------------------------------------------------------------------------------
#
#	オプション変換 - ConvertOption
#	--------------------------------------
#	引　数：$opt : オプション
#	戻り値：結果配列
#
#------------------------------------------------------------------------------------------------------------
sub ConvertOption
{
	my ($opt) = @_;
	
	$opt = '' if (!defined $opt);
	
	# 初期値
	my @ret = (
		-1,	# ラストフラグ
		-1,	# 開始行
		-1,	# 終了行
		-1,	# >>1非表示フラグ
		-1	# 単独表示フラグ
	);
	
	# 最新n件(1無し)
	if ($opt =~ /l(\d+)n/) {
		$ret[0] = 1;
		$ret[1] = $1 + 1;
		$ret[2] = $1 + 1;
		$ret[3] = 1;
	}
	# 最新n件(1あり)
	elsif ($opt =~ /l(\d+)/) {
		$ret[0] = 1;
		$ret[1] = $1;
		$ret[2] = $1;
		$ret[3] = 0;
	}
	# n-m(1無し)
	elsif ($opt =~ /(\d+)-(\d+)n/) {
		$ret[0] = 0;
		$ret[1] = $1;
		$ret[2] = $2;
		$ret[3] = 1;
	}
	# n-m(1あり)
	elsif ($opt =~ /(\d+)-(\d+)/) {
		$ret[0] = 0;
		$ret[1] = $1;
		$ret[2] = $2;
		$ret[3] = 0;
	}
	# n以降(1無し)
	elsif ($opt =~ /(\d+)-n/) {
		$ret[0] = 0;
		$ret[1] = $1;
		$ret[2] = -1;
		$ret[3] = 1;
	}
	# n以降(1あり)
	elsif ($opt =~ /(\d+)-/) {
		$ret[0] = 0;
		$ret[1] = $1;
		$ret[2] = -1;
		$ret[3] = 0;
	}
	# nまで(1あり)
	elsif ($opt =~ /-(\d+)/) {
		$ret[0] = 0;
		$ret[1] = 1;
		$ret[2] = $1;
		$ret[3] = 0;
	}
	# n表示(1無し)
	elsif ($opt =~ /(\d+)n/) {
		$ret[0] = 0;
		$ret[1] = $1;
		$ret[2] = $1;
		$ret[3] = 1;
		$ret[4] = 1;
	}
	# n表示(1あり)
	elsif ($opt =~ /(\d+)/) {
		$ret[0] = 0;
		$ret[1] = $1;
		$ret[2] = $1;
		$ret[3] = 1;
		$ret[4] = 1;
	}
	
	return @ret;
}

#------------------------------------------------------------------------------------------------------------
#
#	パス生成 - CreatePath
#	-------------------------------------------
#	引　数：$Sys  : SYSTEM
#			$mode : 0:read 1:r
#			$bbs  : BBSキー
#			$key  : スレッドキー
#			$opt  : オプション
#	戻り値：生成されたパス
#
#------------------------------------------------------------------------------------------------------------
sub CreatePath
{
	my $this = shift;
	my ($Sys, $mode, $bbs, $key, $opt) = @_;
	
	my $path = $Sys->Get('SERVER') . $Sys->Get('CGIPATH') . '/read.cgi';
	
	# QUERY_STRINGパス生成
	if ($Sys->Get('PATHKIND')) {
		my @opts = ConvertOption($opt);
		
		# ベース作成
		$path .= "?bbs=$bbs&key=$key";
		
		# 最新n件表示
		if ($opts[0]) {
			$path .= "&last=$opts[1]";
		}
		# 指定表示
		else {
			$path .= "&st=$opts[1]";
			$path .= "&to=$opts[2]";
		}
		
		# >>1表示の付加
		$path .= '&nofirst=' . ($opts[3] == 1 ? 'true' : 'false');
	}
	# PATH_INFOパス生成
	else {
		$path .= "/$bbs/$key/$opt";
	}
	
	return $path;
}

#------------------------------------------------------------------------------------------------------------
#
#	日付取得 - GetDate
#	--------------------------------------
#	引　数：$Set  : SETTING.TXT
#			$msect : msec on/off
#	戻り値：日付文字列
#
#------------------------------------------------------------------------------------------------------------
sub GetDate
{
	my $this = shift;
	my ($Set, $msect) = @_;
	
	$ENV{'TZ'} = 'JST-9';
	my @info = localtime time;
	$info[5] += 1900;
	$info[4] += 1;
	
	# 曜日の取得
	my $week = ('日', '月', '火', '水', '木', '金', '土')[$info[6]];
	if (defined $Set && ! $Set->Equal('BBS_YMD_WEEKS', '')) {
		$week = (split(/\//, $Set->Get('BBS_YMD_WEEKS')))[$info[6]];
	}
	
	my $str = '';
	$str .= sprintf('%04d/%02d/%02d', $info[5], $info[4], $info[3]);
	$str .= "($week)" if ($week ne '');
	$str .= sprintf(' %02d:%02d:%02d', $info[2], $info[1], $info[0]);
	
	# msecの取得
	if ($msect) {
		eval {
			require Time::HiRes;
			my $times = Time::HiRes::time();
			$str .= sprintf(".%02d", ($times * 100) % 100);
		};
	}
	
	return $str;
	
}

#------------------------------------------------------------------------------------------------------------
#
#	シリアル値から日付文字列を取得する
#	-------------------------------------------------------------------------------------
#	@param	$serial	シリアル値
#	@param	$mode	0:時間表示有り 1:日付のみ
#	@return	日付文字列
#
#------------------------------------------------------------------------------------------------------------
sub GetDateFromSerial
{
	my $this = shift;
	my ($serial, $mode) = @_;
	
	$ENV{'TZ'} = 'JST-9';
	my @info = localtime $serial;
	$info[5] += 1900;
	$info[4] += 1;
	
	my $str = sprintf('%04d/%02d/%02d', $info[5], $info[4], $info[3]);
	$str .= sprintf(' %02d:%02d', $info[2], $info[1]) if (!$mode);
	
	return $str;
}

#------------------------------------------------------------------------------------------------------------
#
#	ID部分文字列生成
#	-------------------------------------------------------------------------------------
#	@param	$Set	SETTING
#	@param	$Form	FORM
#	@param	$Sec	
#	@param	$id		ID
#	@param	$koyuu	端末固有番号
#	@param	$type	端末識別子
#	@return	ID部分文字列
#
#------------------------------------------------------------------------------------------------------------
sub GetIDPart
{
	my $this = shift;
	my ($Set, $Form, $Sec, $id, $capID, $koyuu, $type) = @_;
	
	my $noid = $Sec->IsAuthority($capID, $ZP::CAP_DISP_NOID, $Form->Get('bbs'));
	my $noslip = $Sec->IsAuthority($capID, $ZP::CAP_DISP_NOSLIP, $Form->Get('bbs'));
	my $customid = $Sec->IsAuthority($capID, $ZP::CAP_DISP_CUSTOMID, $Form->Get('bbs'));
	
	# ID表示無し
	if ($Set->Equal('BBS_NO_ID', 'checked')) {
		return '';
	}
	
	# ホスト表示
	elsif ($Set->Equal('BBS_DISP_IP', 'checked')) {
		my $str = '???';
		if ($noid) {
			$str = '???';
		} elsif ($type eq 'O') {
			$str = "$koyuu $ENV{'REMOTE_HOST'}";
		} elsif ($type eq 'P') {
			$str = "$koyuu $ENV{'REMOTE_HOST'} (($ENV{HTTP_CF_CONNECTING_IP}) ? $ENV{HTTP_CF_CONNECTING_IP} : $ENV{REMOTE_ADDR};)";
		} else {
			$str = "$koyuu";
		}
		if (!$noslip && $Set->Get('BBS_SLIP')) {
			$str .= " $type";
		}
		return "HOST:$str";
	}
	
	# IP表示 Ver.Siberia
	elsif ($Set->Equal('BBS_DISP_IP', 'siberia')){
		my $str = '???';
		if ($noid) {
			$str = '???';
		} elsif ($type eq 'P') {
			$str = "$ENV{'REMOTE_P2'}";
		} else {
			$str = "($ENV{HTTP_CF_CONNECTING_IP}) ? $ENV{HTTP_CF_CONNECTING_IP} : $ENV{REMOTE_ADDR}";
		}
		if (!$noslip && $Set->Get('BBS_SLIP')) {
			$str .= " $type";
		}
		return "発信元:$str";
	}
	
	# IP表示 Ver.Karafuto
	elsif ($Set->Equal('BBS_DISP_IP', 'karafuto')) {
		my $str = '???';
		if ($noid) {
			$str = '???';
		} elsif ($type eq 'P') {
			$str = "$ENV{'HTTP_X_P2_CLIENT_IP'} ($koyuu)";
		} elsif ($type eq 'O') {
			$str = "($ENV{HTTP_CF_CONNECTING_IP}) ? $ENV{HTTP_CF_CONNECTING_IP} : $ENV{REMOTE_ADDR} ($koyuu)";
		} else {
			$str = "($ENV{HTTP_CF_CONNECTING_IP}) ? $ENV{HTTP_CF_CONNECTING_IP} : $ENV{REMOTE_ADDR};";
		}
		if (!$noslip && $Set->Get('BBS_SLIP')) {
			$str .= " $type";
		}
		return "発信元:$str";
	}
	
	# 各キャップ専用ID
	elsif ($customid && $Sec->Get($capID, 'CUSTOMID', 1) ne '') {
		my $str = $Sec->Get($capID, 'CUSTOMID', 1);
		if (!$noslip && $Set->Get('BBS_SLIP')) {
			$str .= " $type";
		}
		return "ID:$str";
	}
	
	# ID表示
	else {
		my $str = '???';
		if ($noid) {
			$str = '???';
		} elsif ($Set->Equal('BBS_FORCE_ID', 'checked')) {
			$str = $id;
		} elsif ($Form->IsInput(['mail'])) {
			$str = '???';
		} else {
			$str = $id;
		}
		if (!$noslip && $Set->Get('BBS_SLIP')) {
			$str .= "$type";
		}
		return "ID:$str";
	}
}

#------------------------------------------------------------------------------------------------------------
#
#	特殊文字変換 - ConvertCharacter0
#	--------------------------------------
#	引　数：$data : 変換元データ(参照)
#	戻り値：なし
#
#------------------------------------------------------------------------------------------------------------
sub ConvertCharacter0
{
	my $this = shift;
	my ($data) = @_;
	
	$$data = '' if (!defined $$data);
	
	$$data =~ s/^($ZP::RE_SJIS*?)＃/$1#/g;
}

#------------------------------------------------------------------------------------------------------------
#
#	特殊文字変換 - ConvertCharacter1
#	--------------------------------------
#	引　数：$data : 変換元データ(参照)
#			$mode : 
#	戻り値：なし
#
#------------------------------------------------------------------------------------------------------------
sub ConvertCharacter1
{
	my $this = shift;
	my ($data, $mode) = @_;
	
	$$data = '' if (!defined $$data);
	
	# all
	$$data =~ s/</&lt;/g;
	$$data =~ s/>/&gt;/g;
	$$data =~ s/&#10;//g;
	$$data =~ s/&#13;//g;
	
	# mail
	if ($mode == 1) {
		$$data =~ s/"/&quot;/g;#"
	}
	
	# text
	if ($mode == 2) {
		$$data =~ s/\n/<br>/g;
	}
	# not text
	else {
		$$data =~ s/\n//g;
	}
}

#------------------------------------------------------------------------------------------------------------
#
#	禁則文字変換 - ConvertCharacter2
#	--------------------------------------
#	引　数：$data : 変換元データ(参照)
#			$mode : 
#	戻り値：なし
#
#------------------------------------------------------------------------------------------------------------
sub ConvertCharacter2
{
	my $this = shift;
	my ($data, $mode) = @_;
	
	$$data = '' if (!defined $$data);
	
	# name mail
	if ($mode == 0 || $mode == 1) {
		$$data =~ s/★/☆/g;
		$$data =~ s/◆/◇/g;
  		$$data =~ s/&#0{0,}9733;/&#0{0,}9734;/g;
		$$data =~ s/&#0{0,}9670;/&#0{0,}9671;/g;
		$$data =~ s/&#(x|X)0{0,}2605;/&#x2606;/g;
		$$data =~ s/&#(x|X)0{0,}25(c|C)6;/&#x25c7;/g;
		$$data =~ s/削除/”削除”/g;
	}
	
	# name
	if ($mode == 0) {
		$$data =~ s/管理/”管理”/g;
		$$data =~ s/管直/”管直”/g;
		$$data =~ s/復帰/”復帰”/g;
	}
}

#------------------------------------------------------------------------------------------------------------
#
#	特殊文字変換 - ConvertFusianasan
#	--------------------------------------
#	引　数：$data : 変換元データ(参照)
#			$host : 
#	戻り値：なし
#
#------------------------------------------------------------------------------------------------------------
sub ConvertFusianasan
{
	my $this = shift;
	my ($data, $host) = @_;
	
	$$data = '' if (!defined $$data);
	
	$$data =~ s/山崎渉/fusianasan/g;
	$$data =~ s|^($ZP::RE_SJIS*?)fusianasan|$1</b>$host<b>|g;
	$$data =~ s|^($ZP::RE_SJIS*?)fusianasan|$1 </b>$host<b>|g;
}

#------------------------------------------------------------------------------------------------------------
#
#	連続アンカー検出 - IsAnker
#	--------------------------------------
#	引　数：$text : 検査対象テキスト
#			$num  : 最大アンカー数
#	戻り値：0:許容内 1:だめぽ
#
#------------------------------------------------------------------------------------------------------------
sub IsAnker
{
	my $this = shift;
	my ($text, $num) = @_;
	
	$_ = $$text;
	my $cnt = s/&gt;&gt;([1-9])//g;
	
	return ($cnt > $num ? 1 : 0);
}

#------------------------------------------------------------------------------------------------------------
#
#	リファラ判断 - IsReferer
#	--------------------------------------
#	引　数：$Sys : SYSTEM
#	戻り値：許可なら0,NGなら1
#
#------------------------------------------------------------------------------------------------------------
sub IsReferer
{
	my $this = shift;
	my ($Sys, $pENV) = @_;
	
	my $svr = $Sys->Get('SERVER');
	if ($pENV->{'HTTP_REFERER'} =~ /\Q$svr\E/) {		# 自鯖からならOK
		return 0;
	}
	if ($pENV->{'HTTP_USER_AGENT'} =~ /Monazilla/) {	# ２ちゃんツールもOK
		return 0;
	}
	return 1;
}

#------------------------------------------------------------------------------------------------------------
#
#	プロクシチェック - IsProxy
#	--------------------------------------
#	引　数：$Sys   : SYSTEM
#			$Form  : 
#			$from  : 名前欄
#			$mode  : エージェント
#	戻り値：プロクシなら対象ポート番号
#
#------------------------------------------------------------------------------------------------------------
sub IsProxy
{
	my $this = shift;
	my ($Sys, $Form, $from, $mode) = @_;
	
	# 携帯, iPhone(3G回線) はプロキシ規制を回避する
	return 0 if ($mode eq 'O' || $mode eq 'i');
	
	my @dnsbls = ();
	push(@dnsbls, 'zen.spamhaus.org') if($Sys->Get('SPAMHAUS'));
	push(@dnsbls, 'bl.spamcop.net') if($Sys->Get('SPAMCOP'));
    push(@dnsbls, 'b.barracudacentral.org') if($Sys->Get('BARRACUDA'));
	
	# DNSBL問い合わせ
	my $addr = join('.', reverse( split(/\./, (($ENV{HTTP_CF_CONNECTING_IP}) ? $ENV{HTTP_CF_CONNECTING_IP} : $ENV{REMOTE_ADDR}))));
	foreach my $dnsbl (@dnsbls) {
		if (CheckDNSBL("$addr.$dnsbl") eq '127.0.0.2') {
			$Form->Set('FROM', "</b> [—\{}\@{}\@{}-] <b>$from");
			return ($mode eq 'P' ? 0 : 1);
		}
	}
	
	return 0;
}
#簡易版
sub IsProxyLite
{
	my $PROXY = 0;

	# HTTP 環境変数をチェック
	if ($ENV{'HTTP_X_FORWARDED_FOR'} && $ENV{'REMOTE_ADDR'} ne $ENV{'HTTP_X_FORWARDED_FOR'}) {
		$PROXY = 1;
	}
	if ($ENV{'HTTP_VIA'}) {
		$PROXY = 1;
	}
	if ($ENV{'HTTP_FORWARDED'}) {
		$PROXY = 1;
	}
	if ($ENV{'HTTP_CACHE_INFO'}) {
		$PROXY = 1;
	}
	if ($ENV{'HTTP_CLIENT_IP'}) {
		$PROXY = 1;
	}
	if ($ENV{'HTTP_PROXY_CONNECTION'}) {
		$PROXY = 1;
	}
	if ($ENV{'HTTP_SP_HOST'}) {
		$PROXY = 1;
	}
	if ($ENV{'HTTP_X_LOCKING'}) {
		$PROXY = 1;
	}

	return $PROXY;
}

#------------------------------------------------------------------------------------------------------------
#
#	DNSBL正引き(timeout付き) - CheckDNSBL
#	--------------------------------------
#	引　数：$host : 正引きするHOST
#	戻り値：プロキシであれば127.0.0.2
#
#------------------------------------------------------------------------------------------------------------
sub CheckDNSBL
{
	my ($host) = @_;
	
	my $ret = eval {
		require Net::DNS;
		my $res = Net::DNS::Resolver->new;
		$res->tcp_timeout(1);
		$res->udp_timeout(1);
		$res->retry(1);
		
		if ((my $query = $res->query($host))) {
			my @ans = $query->answer;
			
			foreach (@ans) {
				return $_->address;
			}
		}
		if ($res->errorstring eq 'query timed out') {
			return '127.0.0.0';
		}
	};
	
	return $ret if (defined $ret);
	
	if ($@) {
		require Net::DNS::Lite;
		my $res = Net::DNS::Lite->new(
			server => [ qw(8.8.4.4 8.8.8.8) ], # google public dns
			timeout => [2, 3],
		);
		
		my @ans = $res->resolve($host, 'a');
		return $_->[4] foreach (@ans);
	}
	
	return '127.0.0.1';
}

#------------------------------------------------------------------------------------------------------------
#
#	パス合成・正規化 - MakePath * not mkdir/mkpath
#	--------------------------------------
#	引　数：$path1 : パス1
#			$path2 : パス2
#	戻り値：正規化パス
#
#------------------------------------------------------------------------------------------------------------
sub MakePath
{
	my $this = (ref($_[0]) eq 'DATA_UTILS' ? shift : undef);
	my ($path1, $path2) = @_;
	
	$path1 = '.' if (! defined $path1 || $path1 eq '');
	$path2 = '.' if (! defined $path2 || $path2 eq '');
	
	my @dir1 = ($path1 =~ m[^/|[^/]+]g);
	my @dir2 = ($path2 =~ m[^/|[^/]+]g);
	
	my $absflg = 0;
	if ($dir2[0] eq '/') {
		$absflg = 1;
		@dir1 = @dir2;
	}
	else {
		push @dir1, @dir2;
	}
	
	my @dir3 = ();
	
	my $depth = 0;
	for my $i (0 .. $#dir1) {
		if ($i == 0 && $dir1[$i] eq '/') {
			$absflg = 1;
		}
		elsif ($dir1[$i] eq '.' || $dir1[$i] eq '') {
		}
		elsif ($dir1[$i] eq '..') {
			if ($depth >= 1) {
				pop @dir3;
			}
			else {
				if ($absflg) {
					last;
				}
				if ($#dir3 == -1 || $dir3[$#dir3] eq '..') {
					push @dir3, '..';
				}
				else {
					pop @dir3;
				}
			}
			$depth--;
		}
		else {
			push @dir3, $dir1[$i];
			$depth++;
		}
	}
	
	my $path3;
	if ($#dir3 == -1) {
		$path3 = ($absflg ? '/' : '.');
	}
	else {
		$path3 = ($absflg ? '/' : '') . join('/', @dir3);
	}
	
	return $path3;
}
#BBS SLIP生成
sub BBS_SLIP
{
	my ($ip_addr, $remoho, $ua, $bbsslip) = @_;
	my ($slip_ip, $slip_remoho, $slip_ua);

	use Digest::MD5 qw(md5_hex);
	use Net::Whois::Raw;
	use Geo::IP;

	#bbs_slipに使用する文字
	my @slip_char = (0..9, "a".."z", "A".."Z", ".", "/");
	#slip_ip生成
	$ip_addr =~ /^(\d{1,4})\.(\d{1,4})/;
	my $ip_char1 = $slip_char[$1 % 64];
	my $ip_char2 = $slip_char[$2 % 64];
	$slip_ip = $ip_char1 . $ip_char2;

	#slip_remoho生成
	if ($remoho eq "") {
		$slip_remoho = "none";
	}else {
		$remoho =~ /^([a-zA-Z]+)[\d\-\.]*([a-zA-Z][a-zA-Z\d\.\-]+)$/;
		my $remoho_name = "$1 $2";
		my $remoho_dig = md5_hex($remoho_name);
		$remoho_dig =~ /^(.{2})(.{2})/;
		my $remoho_char1 = $slip_char[hex($1) % 64];
		my $remoho_char2 = $slip_char[hex($2) % 64];
		$slip_remoho = $remoho_char1 . $remoho_char2;
	}

	#slip_ua生成
	my $ua_dig = md5_hex($ua);
	$ua_dig =~ /^(.{2})(.{2})(.{2})(.{2})/;
	my $ua_char1 = $slip_char[hex($1) % 64];
	my $ua_char2 = $slip_char[hex($2) % 64];
	my $ua_char3 = $slip_char[hex($3) % 64];
	my $ua_char4 = $slip_char[hex($4) % 64];
	$slip_ua = $ua_char1 . $ua_char2 . $ua_char3 . $ua_char4;


	#スマホ・タブレット判定
	my $fixed_nickname_end = "";
	my $mobile_nickname_end = "";
	if ($ua =~ /.*(iphone|ipad|android|mobile).*/i) {
		$fixed_nickname_end = "W";
		$mobile_nickname_end = "M";
	}else {
		$mobile_nickname_end = "T";
	}


	#bbs_slipの初期設定
	my $slip_id = "";
	my $slip_nickname = "ﾜｯﾁｮｲ${fixed_nickname_end}";
	my $slip_aa = $slip_ip;
	my $slip_bb = $slip_remoho;
	my $slip_cccc = $slip_ua;


	#モバイル回線判定用のリモホ・事業者名・IP
	my @mobile_remoho = (
		".*\\.openmobile\\.ne\\.jp",
		".*\\.panda-world\\.ne\\.jp",
		"KD027.*\\.au-net\\.ne\\.jp",
		"KD036.*\\.au-net\\.ne\\.jp",
		"KD106.*\\.au-net\\.ne\\.jp",
		"KD111.*\\.au-net\\.ne\\.jp",
		"KD119.*\\.au-net\\.ne\\.jp",
		"KD182.*\\.au-net\\.ne\\.jp",
		".*\\.msa\\.spmode\\.ne\\.jp",
		".*\\.msb\\.spmode\\.ne\\.jp",
		".*\\.msc\\.spmode\\.ne\\.jp",
		".*\\.msd\\.spmode\\.ne\\.jp",
		".*\\.mse\\.spmode\\.ne\\.jp",
		".*\\.msf\\.spmode\\.ne\\.jp",
		".*\\.fix\\.mopera\\.net",
		".*\\.air\\.mopera\\.net",
		".*\\.vmobile\\.jp",
		".*\\.bmobile\\.ne\\.jp",
		".*\\.mineo\\.jp",
		".*omed01\\.tokyo\\.ocn\\.ne\\.jp",
		".*omed01\\.osaka\\.ocn\\.ne\\.jp",
		".*mobac01\\.tokyo\\.ocn\\.ne\\.jp",
		".*mobac01\\.osaka\\.ocn\\.ne\\.jp",
		".*\\.mvno\\.rakuten\\.jp",
		".*\\.nttpc\\.ne\\.jp",
		"UQ.*au-net\\.ne\\.jp",
		"dcm\\d(?:-\\d+){4}\\.tky\\.mesh\\.ad\\.jp",
		"neoau\\d(?:-\\d+){4}\\.tky\\.mesh\\.ad\\.jp",
		".*\\.ap\\.dream\\.jp",
		".*\\.ap\\.mvno\\.net",
		"fenics\\d+\\.wlan\\.ppp\\.infoweb\\.ne\\.jp"
	);
	my @mobile_whois = (
		"Plus One marketing",
		"LogicLinks",
		"SORASIM"
	);
	my @rakuten_mno_ip = (
		"101\\.102\\.(?:\\d|[1-5]\\d|6[0-3])\\.\\d{1,3}",
		"103\\.124\\.[0-3]\\.\\d{1,3}",
		"110\\.165\\.(?:1(?:2[89]|[3-9]\\d)|2\\d{2})\\.\\d{1,3}",
		"119\\.30\\.(?:19[2-9]|2\\d{2})\\.\\d{1,3}",
		"119\\.31\\.1(?:2[89]|[3-5]\\d)\\.\\d{1,3}",
		"133\\.106\\.(?:1(?:2[89]|[3-9]\\d)|2\\d{2})\\.\\d{1,3}",
		"133\\.106\\.(?:1[6-9]|2\\d|3[01])\\.\\d{1,3}",
		"133\\.106\\.(?:3[2-9]|[45]\\d|6[0-3])\\.\\d{1,3}",
		"133\\.106\\.(?:6[4-9]|[7-9]\\d|1(?:[01]\\d|2[0-7]))\\.\\d{1,3}",
		"133\\.106\\.(?:[89]|1[0-5])\\.\\d{1,3}",
		"157\\.192(?:\\.\\d{1,3}){2}",
		"193\\.114\\.(?:19[2-9]|2\\d{2})\\.\\d{1,3}",
		"193\\.114\\.(?:3[2-9]|[45]\\d|6[0-3])\\.\\d{1,3}",
		"193\\.114\\.(?:6[4-9]|[78]\\d|9[0-5])\\.\\d{1,3}",
		"193\\.115\\.(?:\\d|[12]\\d|3[01])\\.\\d{1,3}",
		"193\\.117\\.(?:[9][6-9]|1(?:[01]\\d|2[0-7]))\\.\\d{1,3}",
		"193\\.118\\.(?:\\d|[12]\\d|3[01])\\.\\d{1,3}",
		"193\\.118\\.(?:6[4-9]|[78]\\d|9[0-5])\\.\\d{1,3}",
		"193\\.119\\.(?:1(?:2[89]|[3-9]\\d)|2\\d{2})\\.\\d{1,3}",
		"193\\.82\\.1(?:[6-8]\\d|9[01])\\.\\d{1,3}",
		"194\\.193\\.2(?:2[4-9]|[34]\\d|5[0-5])\\.\\d{1,3}",
		"194\\.193\\.(?:6[4-9]|[78]\\d|9[0-5])\\.\\d{1,3}",
		"194\\.223\\.(?:[9][6-9]|1(?:[01]\\d|2[0-7]))\\.\\d{1,3}",
		"202\\.176\\.(?:1[6-9]|2\\d|3[01])\\.\\d{1,3}",
		"202\\.216\\.(?:\\d|1[0-5])\\.\\d{1,3}",
		"210\\.157\\.(?:19[2-9]|2(?:[01]\\d|2[0-3]))\\.\\d{1,3}",
		"211\\.133\\.(?:[6-8]\\d|9[01])\\.\\d{1,3}",
		"211\\.7\\.(?:[9][6-9]|1(?:[01]\\d|2[0-7]))\\.\\d{1,3}",
		"219\\.105\\.1(?:4[4-9]|5\\d)\\.\\d{1,3}",
		"219\\.105\\.(?:19[2-9]|2\\d{2})\\.\\d{1,3}",
		"219\\.106\\.(?:\\d{1,2}|1(?:[01]\\d|2[0-7]))\\.\\d{1,3}"
	);

	#モバイル回線のslip_id
	my @mobile_ids = (
		"Sr",
		"Sp",
		"Sa",
		"Sd",
		"SD",
		"MM"
	);

	#モバイル回線のニックネーム
	my @mobile_nicknames = (
		"ｵｯﾍﾟｹ${mobile_nickname_end}",
		"ｻｻｸｯﾃﾛ${mobile_nickname_end}",
		"ｱｳｱｳｱｰ${mobile_nickname_end}",
		"ｱｳｱｳｲｰ${mobile_nickname_end}",
		"ｱｳｱｳｳｰ${mobile_nickname_end}",
		"ｱｳｱｳｴｰ${mobile_nickname_end}",
		"ｱｳｱｳｵｰ${mobile_nickname_end}",
		"ｱｳｱｳｶｰ${mobile_nickname_end}",
		"ｽﾌﾟｰ${mobile_nickname_end}",
		"ｽﾌﾟｯｯ${mobile_nickname_end}",
		"ｽｯﾌﾟ${mobile_nickname_end}",
		"ｽｯｯﾌﾟ${mobile_nickname_end}",
		"ｽﾌﾟﾌﾟ${mobile_nickname_end}",
		"ｽﾌｯ${mobile_nickname_end}",
		"ﾍﾟﾗﾍﾟﾗ${mobile_nickname_end}",
		"ｴｱﾍﾟﾗ${mobile_nickname_end}",
		"ﾌﾞｰｲﾓ${mobile_nickname_end}",
		"ﾍﾞｰｲﾓ${mobile_nickname_end}",
		"ｵｲｺﾗﾐﾈｵ${mobile_nickname_end}",
		"ﾜﾝﾄﾝｷﾝ${mobile_nickname_end}",
		"ﾜﾝﾐﾝｸﾞｸ${mobile_nickname_end}",
		"ﾊﾞｯﾄﾝｷﾝ${mobile_nickname_end}",
		"ﾊﾞｯﾐﾝｸﾞｸ${mobile_nickname_end}",
		"ﾗｸｯﾍﾟﾍﾟ${mobile_nickname_end}",
		"ﾗｸﾗｯﾍﾟ${mobile_nickname_end}",
		"ｱｳｱｳｸｰ${mobile_nickname_end}",
		"ﾄﾞｺｸﾞﾛ${mobile_nickname_end}",
		"ﾄﾞﾅﾄﾞﾅｰ${mobile_nickname_end}",
		"ﾄﾝﾓｰ${mobile_nickname_end}",
		"ｱﾒ${mobile_nickname_end}",
		"ﾆｬﾌﾆｬ${mobile_nickname_end}",
		"ｲﾙｸﾝ${mobile_nickname_end}",
		"ｹﾞﾏｰ${mobile_nickname_end}",
		"ﾌﾘｯﾃﾙ${mobile_nickname_end}"
	);

	#公衆Wi-Fiのリモホ・ネットワーク名・IP
	my @fwifi_remoho = (
		".*\\.m-zone\\.jp",
		"\\d+\\.wi-fi\\.kddi\\.com",
		".*\\.wi-fi\\.wi2\\.ne\\.jp",
		".*\\.family-wifi\\.jp"
	);
	my @fwifi_whois = (
		"INPLUS-FWIFI",
		"FON"
	);
	my $lawson_ip = "210\\.227\\.19\\.[67]\\d\$";
	#公衆Wi-FiのID
	my $fwifi_id = "FF";
	#公衆Wi-Fiのニックネーム
	my @fwifi_nicknames = (
		"ｴﾑｿﾞﾈ${fixed_nickname_end}[公衆]",
		"ｱｳｳｨﾌ${fixed_nickname_end}[公衆]",
		"ﾜｲｰﾜ2${fixed_nickname_end}[公衆]",
		"ﾌｧﾐﾏ${fixed_nickname_end}[公衆]",
		"ﾌｫﾝﾌｫﾝ${fixed_nickname_end}[公衆]",
		"ﾏｸﾄﾞ${fixed_nickname_end}[公衆]"
	);

	#逆引き判定
	if ($slip_remoho eq "none") { #逆引きできない場合
		my $isunknown = "yes";
		my $res = whois($ip_addr);

		#モバイル回線判定
		my $mobile_nickname_idx = -1;
		for my $name (@mobile_whois) {
			if ($res =~ /.*${name}.*/) {
				$slip_id = "MM";
				$slip_nickname = $mobile_nicknames[$mobile_nickname_idx];
				$slip_aa = $slip_id;
				$slip_bb = $slip_ip;
				$isunknown = "no";
				last;
			}
			$mobile_nickname_idx--;
		}
		#楽天モバイル(MNO)判定
		if ($isunknown eq "yes") {
			for my $name (@rakuten_mno_ip) {
				if ($ip_addr =~ /${name}/) {
					$slip_id = "MM";
					$slip_nickname = "ﾃﾃﾝﾃﾝﾃﾝM";
					$slip_aa = $slip_id;
					$slip_bb = $slip_ip;
					$isunknown = "no";
					last;
				}
			}
		}

		#公衆判定
		if ($isunknown eq "yes") {
			my $fwifi_nickname_idx = -1;
			for my $name (@fwifi_whois) {
				if ($res =~ /.*${name}.*/) {
					$slip_id = $fwifi_id;
					$slip_nickname = $fwifi_nicknames[$fwifi_nickname_idx];
					$slip_aa = $slip_id;
					$slip_bb = $slip_ip;
					$isunknown = "no";
					last;
				}
				$fwifi_nickname_idx--;
			}
		}
		#ローソン判定
		if ($isunknown eq "yes") {
			if ($ip_addr =~ /${lawson_ip}/) {
				$slip_id = "FF";
				$slip_nickname = "ﾛｰｿﾝ${fixed_nickname_end}[公衆]";
				$slip_aa = $slip_id;
				$slip_bb = $slip_ip;
				$isunknown = "no";
			}
		}

		#逆引き不可能 ｱﾝﾀﾀﾞﾚ
		if ($isunknown eq "yes") {
			$slip_id = "Un";
			$slip_nickname = "ｱﾝﾀﾀﾞﾚ${fixed_nickname_end}";
			$slip_aa = $slip_id;
			$slip_bb = $slip_ip;
		}
	}else{ #逆引きできる場合
		my $ismobile = 0;
		#モバイル回線判定
		my $mobile_id_idx = 0;
		my $mobile_nickname_idx = 0;
		for my $name (@mobile_remoho) {
			if ($remoho =~ /^${name}$/) {
				$slip_id = $mobile_ids[$mobile_id_idx];
				$slip_nickname = $mobile_nicknames[$mobile_nickname_idx];
				$slip_aa = $slip_id;
				$slip_bb = $slip_ip;
				$ismobile = 1;
				last;
			}
			if ($mobile_id_idx < 2 || $mobile_nickname_idx =~ /^(7|9|15)$/) {
				$mobile_id_idx++;
			}
			$mobile_nickname_idx++;
		}

		#公衆判定
		if ($ismobile == 0) {
			my $fwifi_nickname_idx = 0;
			for my $name (@fwifi_remoho) {
				if ($remoho =~ /^${name}$/) {
					$slip_id = $fwifi_id;
					$slip_nickname = $fwifi_nicknames[$fwifi_nickname_idx];
					$slip_aa = $slip_id;
					$slip_bb = $slip_ip;
					last;
				}
				$fwifi_nickname_idx++;
			}
		}

  #社畜判定
  if ($ismobile == 0) {
    if ($remoho =~ /^.+\.co\.jp$/) {
      $slip_nickname = "ｼｬﾁｰｸ${fixed_nickname_end}";
    }
  }
}

	# Geo::IPがインストールされているかチェック
	my $geo_ip_installed = eval {
	    require Geo::IP;
	    1;  # 成功
	};

	# 国を判定
	my $gi_dat = "./datas/GeoIPCity.dat";
	if ($geo_ip_installed && -f $gi_dat) {
	    my $gi = Geo::IP->open($gi_dat, GEOIP_STANDARD);
	    my $record = $gi->record_by_addr($ip_addr);
	    my $ip_country =  $record->country_code;
	    if ($ip_country =~ /^(?!.*JP).*$/) {
	        $slip_nickname = "ｶﾞｲｺｰｸ${fixed_nickname_end}[${ip_country}]";
	        $slip_aa = $ip_country;
	        $slip_bb = $slip_ip;
	    }
	}

	#bbs_slipを生成
	my $slip_result = 'undef';
	if($bbsslip eq 'vvv'){
		$slip_result = ${slip_nickname};
	}
	elsif($bbsslip eq 'vvvv'){
		$slip_result = "${slip_nickname} [${ip_addr}]";
	}
	elsif($bbsslip eq 'vvvvv'){
		$slip_result = "${slip_nickname} ${slip_aa}${slip_bb}-${slip_cccc}";
	}
	elsif($bbsslip eq 'vvvvvv'){
		$slip_result = "${slip_nickname} ${slip_aa}${slip_bb}-${slip_cccc} [${ip_addr}]";
	}

	return $slip_result;
}
#============================================================================================================
#	モジュール終端
#============================================================================================================
1;
