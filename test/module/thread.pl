#============================================================================================================
#
#	スレッド情報管理モジュール
#	-------------------------------------------------------------------------------------
#	このモジュールはスレッド情報を管理します。
#	以下の2つのパッケージによって構成されます
#
#	THREAD	: 現行スレッド情報管理
#	POOL_THREAD	: プールスレッド情報管理
#
#============================================================================================================

#============================================================================================================
#
#	スレッド情報管理パッケージ
#
#============================================================================================================
package	THREAD;

use strict;
use utf8;
binmode(STDIN,':encoding(cp932)');
binmode(STDOUT,':encoding(cp932)');
use open IO => ':encoding(cp932)';
#use warnings;

#------------------------------------------------------------------------------------------------------------
#
#	コンストラクタ
#	-------------------------------------------------------------------------------------
#	@param	なし
#	@return	モジュールオブジェクト
#
#------------------------------------------------------------------------------------------------------------
sub new
{
	my $class = shift;
	
	my $obj = {
		'SUBJECT'	=> undef,
		'RES'		=> undef,
		'SORT'		=> undef,
		'NUM'		=> undef,
		'HANDLE'	=> undef,
		'ATTR'		=> undef,
	};
	bless $obj, $class;
	
	return $obj;
}

#------------------------------------------------------------------------------------------------------------
#
#	デストラクタ
#	-------------------------------------------------------------------------------------
#	@param	なし
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub DESTROY
{
	my $this = shift;
	
	my $handle = $this->{'HANDLE'};
	if ($handle) {
		close($handle);
	}
	$this->{'HANDLE'} = undef;
}

#------------------------------------------------------------------------------------------------------------
#
#	オープン
#	-------------------------------------------------------------------------------------
#	@param	$Sys	SYSTEM
#	@return	ファイルハンドル
#
#------------------------------------------------------------------------------------------------------------
sub Open
{
	my $this = shift;
	my ($Sys) = @_;
	
	my $path = $Sys->Get('BBSPATH') . '/' .$Sys->Get('BBS') . '/subject.txt';
	my $fh = undef;
	
	if ($this->{'HANDLE'}) {
		$fh = $this->{'HANDLE'};
		seek($fh, 0, 0);
	}
	else {
		chmod($Sys->Get('PM-TXT'), $path);
		if (open($fh, (-f $path ? '+<' : '>'), $path)) {
			flock($fh, 2);
			binmode($fh);
			seek($fh, 0, 0);
			$this->{'HANDLE'} = $fh;
		}
		else {
			warn "can't load subject: $path";
		}
	}
	
	return $fh;
}

#------------------------------------------------------------------------------------------------------------
#
#	強制クローズ
#	-------------------------------------------------------------------------------------
#	@param	なし
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub Close
{
	my $this = shift;
	
	my $handle = $this->{'HANDLE'};
	if ($handle) {
		close($handle);
	}
	$this->{'HANDLE'} = undef;
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド情報読み込み
#	-------------------------------------------------------------------------------------
#	@param	$Sys	SYSTEM
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub Load
{
	my $this = shift;
	my ($Sys) = @_;
	
	$this->{'SUBJECT'} = {};
	$this->{'RES'} = {};
	$this->{'SORT'} = [];
	
	my $fh = $this->Open($Sys) or return;
	my @lines = <$fh>;
	map { s/[\r\n]+\z// } @lines;
	
	my $num = 0;
	foreach (@lines) {
		next if ($_ eq '');
		
		if ($_ =~ /^(.+?)\.dat<>(.*?) ?\(([0-9]+)\)$/) {
			$this->{'SUBJECT'}->{$1} = $2;
			$this->{'RES'}->{$1} = $3;
			push @{$this->{'SORT'}}, $1;
			$num++;
		}
		else {
			warn "invalid line";
			next;
		}
	}
	$this->{'NUM'} = $num;
	
	$this->LoadAttr($Sys);
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド情報保存
#	-------------------------------------------------------------------------------------
#	@param	$Sys	SYSTEM
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub Save
{
	my $this = shift;
	my ($Sys) = @_;
	
	my $fh = $this->Open($Sys) or return;
	my $subject = $this->{'SUBJECT'};
	
	$this->CustomizeOrder();
	
	foreach (@{$this->{'SORT'}}) {
		next if (!defined $subject->{$_});
		print $fh "Shift_JIS","$_.dat<>$subject->{$_} ($this->{'RES'}->{$_})\n";
	}
	
	truncate($fh, tell($fh));
	
	$this->Close();
	my $path = $Sys->Get('BBSPATH') . '/' .$Sys->Get('BBS') . '/subject.txt';
	chmod($Sys->Get('PM-TXT'), $path);
	
	$this->SaveAttr($Sys);
}

#------------------------------------------------------------------------------------------------------------
#
#	オンデマンド式レス数更新
#	-------------------------------------------------------------------------------------
#	@param	$Sys	SYSTEM
#	@param	$id		スレッドID
#	@param	$val	レス数
#	@param	$updown	'', 'top', 'bottom', '+n', '-n'
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub OnDemand
{
	my $this = shift;
	my ($Sys, $id, $val, $updown) = @_;
	
	my $subject = {};
	$this->{'SUBJECT'} = $subject;
	$this->{'RES'} = {};
	$this->{'SORT'} = [];
	
	my $fh = $this->Open($Sys) or return;
	my @lines = <$fh>;
	map { s/[\r\n]+\z// } @lines;
	
	my $num = 0;
	foreach (@lines) {
		next if ($_ eq '');
		
		if ($_ =~ /^(.+?)\.dat<>(.*?) ?\(([0-9]+)\)$/) {
			$subject->{$1} = $2;
			$this->{'RES'}->{$1} = $3;
			push @{$this->{'SORT'}}, $1;
			$num++;
		}
		else {
			warn "invalid line";
			next;
		}
	}
	$this->{'NUM'} = $num;
	
	# レス数更新
	if (exists $this->{'RES'}->{$id}) {
		$this->{'RES'}->{$id} = $val;
	}
	
	# スレッド移動
	if ($updown eq 'top') {
		$this->AGE($id);
	} elsif ($updown eq 'bottom') {
		$this->DAME($id);
	} elsif ($updown =~ /^([\+\-][0-9]+)$/) {
		$this->UpDown($id, int($1));
	}
	
	$this->CustomizeOrder();
	
	# subject書き込み
	seek($fh, 0, 0);
	
	foreach (@{$this->{'SORT'}}) {
		next if (!defined $subject->{$_});
		print $fh "$_.dat<>$subject->{$_} ($this->{'RES'}->{$_})\n";
	}
	
	truncate($fh, tell($fh));
	
	$this->Close();
	my $path = $Sys->Get('BBSPATH') . '/' .$Sys->Get('BBS') . '/subject.txt';
	chmod($Sys->Get('PM-TXT'), $path);
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッドIDセット取得
#	-------------------------------------------------------------------------------------
#	@param	$kind	検索種別('ALL'の場合すべて)
#	@param	$name	検索ワード
#	@param	$pBuf	IDセット格納バッファ
#	@return	キーセット数
#
#------------------------------------------------------------------------------------------------------------
sub GetKeySet
{
	my $this = shift;
	my ($kind, $name, $pBuf) = @_;
	
	my $n = 0;
	
	if ($kind eq 'ALL') {
		$n += push @$pBuf, @{$this->{'SORT'}};
	}
	else {
		foreach my $key (keys %{$this->{$kind}}) {
			if ($this->{$kind}->{$key} eq $name || $kind eq 'ALL') {
				$n += push @$pBuf, $key;
			}
		}
	}
	
	return $n;
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド情報取得
#	-------------------------------------------------------------------------------------
#	@param	$kind		情報種別
#	@param	$key		スレッドID
#	@param	$default	デフォルト
#	@return	スレッド情報
#
#------------------------------------------------------------------------------------------------------------
sub Get
{
	my $this = shift;
	my ($kind, $key, $default) = @_;
	
	my $val = $this->{$kind}->{$key};
	
	return (defined $val ? $val : (defined $default ? $default : undef));
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド情報追加
#	-------------------------------------------------------------------------------------
#	@param	$id			スレッドID
#	@param	$subject	スレッドタイトル
#	@param	$res		レス
#	@return	スレッドID
#
#------------------------------------------------------------------------------------------------------------
sub Add
{
	my $this = shift;
	my ($id, $subject, $res) = @_;
	
	$this->{'SUBJECT'}->{$id} = $subject;
	$this->{'RES'}->{$id} = $res;
	unshift @{$this->{'SORT'}}, $id;
	$this->{'NUM'}++;
	
	return $id;
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド情報設定
#	-------------------------------------------------------------------------------------
#	@param	$id		スレッドID
#	@param	$kind	情報種別
#	@param	$val	設定値
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub Set
{
	my $this = shift;
	my ($id, $kind, $val) = @_;
	
	if (exists $this->{$kind}->{$id}) {
		$this->{$kind}->{$id} = $val;
	}
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド情報削除
#	-------------------------------------------------------------------------------------
#	@param	$id		削除スレッドID
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub Delete
{
	my $this = shift;
	my ($id) = @_;
	
	delete $this->{'SUBJECT'}->{$id};
	delete $this->{'RES'}->{$id};
	# for pool
	#delete $this->{'ATTR'}->{$id};
	
	my $sort = $this->{'SORT'};
	for (my $i = 0; $i < scalar(@$sort); $i++) {
		if ($id eq $sort->[$i]) {
			splice @$sort, $i, 1;
			$this->{'NUM'}--;
			last;
		}
	}
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド属性情報読み込み
#	-------------------------------------------------------------------------------------
#	@param	$Sys	SYSTEM
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub LoadAttr
{
	my $this = shift;
	my ($Sys) = @_;
	
	$this->{'ATTR'} = {};
	
	my $path = $Sys->Get('BBSPATH') . '/' .$Sys->Get('BBS') . '/info/attr.cgi';
	
	if (open(my $fh, '<', $path)) {
		flock($fh, 2);
		my @lines = <$fh>;
		close($fh);       
		map { s/[\r\n]+\z// } @lines;
		
		foreach (@lines) {
			next if ($_ eq '');
			
			my @elem = split(/<>/, $_, -1);
			if (scalar(@elem) < 2) {
				warn "invalid line in $path";
				next;
			}
			
			my $id = $elem[0];
			# for pool, don't skip
			#next if (!defined $this->{'SUBJECT'}->{$id});
			
			my $hash = {};
			foreach (split /[&;]/, $elem[1]) {
				my ($key, $val) = split(/=/, $_, 2);
				$key =~ tr/+/ /;
				$key =~ s/%([0-9a-f][0-9a-f])/pack('C', hex($1))/egi;
				$val =~ tr/+/ /;
				$val =~ s/%([0-9a-f][0-9a-f])/pack('C', hex($1))/egi;
				$hash->{$key} = $val if ($val ne '');
			}
			
			$this->{'ATTR'}->{$id} = $hash;
		}
	}
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド属性情報保存
#	-------------------------------------------------------------------------------------
#	@param	$Sys	SYSTEM
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub SaveAttr
{
	my $this = shift;
	my ($Sys) = @_;
	
	my $path = $Sys->Get('BBSPATH') . '/' .$Sys->Get('BBS') . '/info/attr.cgi';
	
	chmod($Sys->Get('PM-ADM'), $path);
	if (open(my $fh, (-f $path ? '+<' : '>'), $path)) {
		flock($fh, 2);
		binmode($fh);
		seek($fh, 0, 0);
		
		my $Attr = $this->{'ATTR'};
		foreach my $id (keys %$Attr) {
			my $hash = $Attr->{$id};
			next if (!defined $hash);
			
			my $attrs = '';
			while (my ($key, $val) = each %$hash) {
				next if (!defined $val || $val eq '');
				$key =~ s/([^\w])/'%'.unpack('H2', $1)/eg;
				$val =~ s/([^\w])/'%'.unpack('H2', $1)/eg;
				$attrs .= "$key=$val&";
			}
			
			next if ($attrs eq '');
			
			my $data = join('<>',
				$id,
				$attrs,
			);
			
			print $fh "$data\n";
		}
		
		truncate($fh, tell($fh));
		close($fh);
	}
	chmod($Sys->Get('PM-ADM'), $path);
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド属性情報取得
#	-------------------------------------------------------------------------------------
#	@param	$key		スレッドID
#	@param	$attr		属性名
#	@return	スレッド属性情報
#
#------------------------------------------------------------------------------------------------------------
sub GetAttr
{
	my $this = shift;
	my ($key, $attr) = @_;
	
	if (!defined $this->{'ATTR'}) {
		warn "Attr info is not loaded.";
		return;
	}
	my $Attr = $this->{'ATTR'};
	
	my $val = undef;
	$val = $Attr->{$key}->{$attr} if (defined $Attr->{$key});
	
	# undef => empty string
	return (defined $val ? $val : '');
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド属性情報設定
#	-------------------------------------------------------------------------------------
#	@param	$key		スレッドID
#	@param	$attr		属性名
#	@param	$val		属性値
#
#------------------------------------------------------------------------------------------------------------
sub SetAttr
{
	my $this = shift;
	my ($key, $attr, $val) = @_;
	
	if (!defined $this->{'ATTR'}) {
		warn "Attr info is not loaded.";
		return;
	}
	my $Attr = $this->{'ATTR'};
	
	$Attr->{$key} = {} if (!defined $Attr->{$key});
	$Attr->{$key}->{$attr} = $val;
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド属性情報削除
#	-------------------------------------------------------------------------------------
#	@param	$key		スレッドID
#
#------------------------------------------------------------------------------------------------------------
sub DeleteAttr
{
	my $this = shift;
	my ($key) = @_;
	
	if (!defined $this->{'ATTR'}) {
		warn "Attr info is not loaded.";
		return;
	}
	my $Attr = $this->{'ATTR'};
	
	delete $Attr->{$key};
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド数取得
#	-------------------------------------------------------------------------------------
#	@param	なし
#	@return	スレッド数
#
#------------------------------------------------------------------------------------------------------------
sub GetNum
{
	my $this = shift;
	
	return $this->{'NUM'};
}

#------------------------------------------------------------------------------------------------------------
#
#	最後のスレッドID取得
#	-------------------------------------------------------------------------------------
#	@param	なし
#	@return	スレッドID
#
#------------------------------------------------------------------------------------------------------------
sub GetLastID
{
	my $this = shift;
	
	my $sort = $this->{'SORT'};
	return $sort->[$#$sort];
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド順調整
#	-------------------------------------------------------------------------------------
#	@param	なし
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub CustomizeOrder
{
	my $this = shift;
	
	my @float = ();
	my @sort = ();
	
	foreach my $id (@{$this->{'SORT'}}) {
		if ($this->GetAttr($id, 'float')) {
			push @float, $id;
		} else {
			push @sort, $id;
		}
	}
	
	$this->{'SORT'} = [@float, @sort];
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッドあげ
#	-------------------------------------------------------------------------------------
#	@param	スレッドID
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub AGE
{
	my $this = shift;
	my ($id) = @_;
	
	my $sort = $this->{'SORT'};
	for (my $i = 0; $i < scalar(@$sort); $i++) {
		if ($id eq $sort->[$i]) {
			splice @$sort, $i, 1;
			unshift @$sort, $id;
			last;
		}
	}
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッドだめ
#	-------------------------------------------------------------------------------------
#	@param	スレッドID
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub DAME
{
	my $this = shift;
	my ($id) = @_;
	
	my $sort = $this->{'SORT'};
	for (my $i = 0; $i < scalar(@$sort); $i++) {
		if ($id eq $sort->[$i]) {
			splice @$sort, $i, 1;
			push @$sort, $id;
			last;
		}
	}
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド移動
#	-------------------------------------------------------------------------------------
#	@param	$id	スレッドID
#	@param	$n	移動数(+上げ -下げ)
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub UpDown
{
	my $this = shift;
	my ($id, $n) = @_;
	
	my $sort = $this->{'SORT'};
	my $max = scalar(@$sort);
	for (my $i = 0; $i < $max; $i++) {
		if ($id eq $sort->[$i]) {
			my $to = $i - $n;
			$to = 0 if ($to < 0);
			$to = $max-1 if ($to > $max-1);
			splice @$sort, $i, 1;
			splice @$sort, $to, 0, $id;
			last;
		}
	}
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド情報更新
#	-------------------------------------------------------------------------------------
#	@param	$Sys	SYSTEM
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub Update
{
	my $this = shift;
	my ($Sys) = @_;
	
	my $base = $Sys->Get('BBSPATH') . '/' . $Sys->Get('BBS') . '/dat';
	
	$this->CustomizeOrder();
	
	foreach my $id (@{$this->{'SORT'}}) {
		if (open(my $fh, '<', "$base/$id.dat")) {
			flock($fh, 2);
			my $n = 0;
			$n++ while (<$fh>);
			close($fh);
			$this->{'RES'}->{$id} = $n;
		}
		else {
			warn "can't open file: $base/$id.dat";
		}
	}
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド情報完全更新
#	-------------------------------------------------------------------------------------
#	@param	$Sys	SYSTEM
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub UpdateAll
{
	my $this = shift;
	my ($Sys) = @_;
	
	my $psort = $this->{'SORT'};
	$this->{'SORT'} = [];
	$this->{'SUBJECT'} = {};
	$this->{'RES'} = {};
	my $idhash = {};
	my @dirSet = ();
	
	my $base = $Sys->Get('BBSPATH') . '/' . $Sys->Get('BBS') . '/dat';
	my $num	= 0;
	
	# ディレクトリ内一覧を取得
	if (opendir(my $fh, $base)) {
		@dirSet = readdir($fh);
		closedir($fh);
	}
	else {
		warn "can't open dir: $base";
		return;
	}
	
	foreach my $el (@dirSet) {
		if ($el =~ /^(.*)\.dat$/ && open(my $fh, '<', "$base/$el")) {
			flock($fh, 2);
			my $id = $1;
			my $n = 1;
			my $first = <$fh>;
			$n++ while (<$fh>);
			close($fh);
			$first =~ s/[\r\n]+\z//;
			
			my @elem = split(/<>/, $first, -1);
			$this->{'SUBJECT'}->{$id} = $elem[4];
			$this->{'RES'}->{$id} = $n;
			$idhash->{$id} = 1;
			$num++;
		}
	}
	$this->{'NUM'} = $num;
	
	foreach my $id (@$psort) {
		if (defined $idhash->{$id}) {
			push @{$this->{'SORT'}}, $id;
			delete $idhash->{$id};
		}
	}
	foreach my $id (sort keys %$idhash) {
		unshift @{$this->{'SORT'}}, $id;
	}
	
	$this->CustomizeOrder();
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド位置取得
#	-------------------------------------------------------------------------------------
#	@param	$id	スレッドID
#	@return	スレッド位置。取得できない場合は-1
#
#------------------------------------------------------------------------------------------------------------
sub GetPosition
{
	my $this = shift;
	my ($id) = @_;
	
	my $sort = $this->{'SORT'};
	for (my $i = 0; $i < scalar(@$sort); $i++) {
		if ($id eq $sort->[$i]) {
			return $i;
		}
	}
	
	return -1;
}


#============================================================================================================
#
#	プールスレッド情報管理パッケージ
#
#============================================================================================================
package	POOL_THREAD;

use strict;
use utf8;
binmode(STDIN,':encoding(cp932)');
binmode(STDOUT,':encoding(cp932)');
use open IO => ':encoding(cp932)';
#use warnings;

#------------------------------------------------------------------------------------------------------------
#
#	コンストラクタ
#	-------------------------------------------------------------------------------------
#	@param	なし
#	@return	モジュールオブジェクト
#
#------------------------------------------------------------------------------------------------------------
sub new
{
	my $class = shift;
	
	my $obj = {
		'SUBJECT'	=> undef,
		'RES'		=> undef,
		'SORT'		=> undef,
		'NUM'		=> undef,
		'ATTR'		=> undef,
	};
	bless $obj, $class;
	
	return $obj;
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド情報読み込み
#	-------------------------------------------------------------------------------------
#	@param	$Sys	SYSTEM
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub Load
{
	my $this = shift;
	my ($Sys) = @_;
	
	$this->{'SUBJECT'} = {};
	$this->{'RES'} = {};
	$this->{'SORT'} = [];
	
	my $path = $Sys->Get('BBSPATH') . '/' .$Sys->Get('BBS') . '/pool/subject.cgi';
	
	if (open(my $fh, '<', $path)) {
		flock($fh, 2);
		my @lines = <$fh>;
		close($fh);
		map { s/[\r\n]+\z// } @lines;
		
		my $num = 0;
		for (@lines) {
			next if ($_ eq '');
			
			if ($_ =~ /^(.+?)\.dat<>(.*?) ?\(([0-9]+)\)$/) {
				$this->{'SUBJECT'}->{$1} = $2;
				$this->{'RES'}->{$1} = $3;
				push @{$this->{'SORT'}}, $1;
				$num++;
			}
			else {
				warn "invalid line in $path";
				next;
			}
		}
		$this->{'NUM'} = $num;
	}
	
	$this->LoadAttr($Sys);
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド情報保存
#	-------------------------------------------------------------------------------------
#	@param	$Sys	SYSTEM
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub Save
{
	my $this = shift;
	my ($Sys) = @_;
	
	my $path = $Sys->Get('BBSPATH') . '/' .$Sys->Get('BBS') . '/pool/subject.cgi';
	
	chmod($Sys->Get('PM-ADM'), $path);
	if (open(my $fh, (-f $path ? '+<' : '>'), $path)) {
		flock($fh, 2);
		seek($fh, 0, 0);
		binmode($fh);
		
		my $subject = $this->{'SUBJECT'};
		foreach (@{$this->{'SORT'}}) {
			next if (!defined $subject->{$_});
			print $fh "$_.dat<>$subject->{$_} ($this->{'RES'}->{$_})\n";
		}
		
		truncate($fh, tell($fh));
		close($fh);
	}
	else {
		warn "can't save subject: $path";
	}
	chmod($Sys->Get('PM-ADM'), $path);
	
	$this->SaveAttr($Sys);
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッドIDセット取得
#	-------------------------------------------------------------------------------------
#	@param	$kind	検索種別('ALL'の場合すべて)
#	@param	$name	検索ワード
#	@param	$pBuf	IDセット格納バッファ
#	@return	キーセット数
#
#------------------------------------------------------------------------------------------------------------
sub GetKeySet
{
	my $this = shift;
	my ($kind, $name, $pBuf) = @_;
	
	my $n = 0;
	
	if ($kind eq 'ALL') {
		$n += push @$pBuf, @{$this->{'SORT'}};
	}
	else {
		foreach my $key (keys %{$this->{$kind}}) {
			if ($this->{$kind}->{$key} eq $name || $kind eq 'ALL') {
				$n += push @$pBuf, $key;
			}
		}
	}
	
	return $n;
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド情報取得
#	-------------------------------------------------------------------------------------
#	@param	$kind		情報種別
#	@param	$key		スレッドID
#	@param	$default	デフォルト
#	@return	スレッド情報
#
#------------------------------------------------------------------------------------------------------------
sub Get
{
	my $this = shift;
	my ($kind, $key, $default) = @_;
	
	my $val = $this->{$kind}->{$key};
	
	return (defined $val ? $val : (defined $default ? $default : undef));
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド情報追加
#	-------------------------------------------------------------------------------------
#	@param	$id			スレッドID
#	@param	$subject	スレッドタイトル
#	@param	$res		レス
#	@return	スレッドID
#
#------------------------------------------------------------------------------------------------------------
sub Add
{
	my $this = shift;
	my ($id, $subject, $res) = @_;
	
	$this->{'SUBJECT'}->{$id} = $subject;
	$this->{'RES'}->{$id} = $res;
	unshift @{$this->{'SORT'}}, $id;
	$this->{'NUM'}++;
	
	return $id;
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド情報設定
#	-------------------------------------------------------------------------------------
#	@param	$id		スレッドID
#	@param	$kind	情報種別
#	@param	$val	設定値
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub Set
{
	my $this = shift;
	my ($id, $kind, $val) = @_;
	
	if (exists $this->{$kind}->{$id}) {
		$this->{$kind}->{$id} = $val;
	}
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド情報削除
#	-------------------------------------------------------------------------------------
#	@param	$id		削除スレッドID
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub Delete
{
	my $this = shift;
	my ($id) = @_;
	
	delete $this->{'SUBJECT'}->{$id};
	delete $this->{'RES'}->{$id};
	
	my $sort = $this->{'SORT'};
	for (my $i = 0; $i < scalar(@$sort); $i++) {
		if ($id eq $sort->[$i]) {
			splice @$sort, $i, 1;
			$this->{'NUM'}--;
			last;
		}
	}
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド数取得
#	-------------------------------------------------------------------------------------
#	@param	なし
#	@return	スレッド数
#
#------------------------------------------------------------------------------------------------------------
sub GetNum
{
	my $this = shift;
	
	return $this->{'NUM'};
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド属性情報関連
#
#------------------------------------------------------------------------------------------------------------
sub LoadAttr
{
	return THREAD::LoadAttr(@_);
}

sub SaveAttr
{
	return THREAD::SaveAttr(@_);
}

sub GetAttr
{
	return THREAD::GetAttr(@_);
}

sub SetAttr
{
	return THREAD::SetAttr(@_);
}

sub DeleteAttr
{
	return THREAD::DeleteAttr(@_);
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド情報更新
#	-------------------------------------------------------------------------------------
#	@param	$Sys	SYSTEM
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub Update
{
	my $this = shift;
	my ($Sys) = @_;
	my ($id, $base, $n);
	
	$base = $Sys->Get('BBSPATH') . '/' . $Sys->Get('BBS') . '/pool';
	
	foreach my $id (@{$this->{'SORT'}}) {
		if (open(my $fh, '<', "$base/$id.cgi")) {
			flock($fh, 2);
			my $n = 0;
			$n++ while (<$fh>);
			close($fh);
			$this->{'RES'}->{$id} = $n;
		}
		else {
			warn "can't open file: $base/$id.dat";
		}
	}
}

#------------------------------------------------------------------------------------------------------------
#
#	スレッド情報完全更新
#	-------------------------------------------------------------------------------------
#	@param	$Sys	SYSTEM
#	@return	なし
#
#------------------------------------------------------------------------------------------------------------
sub UpdateAll
{
	my $this = shift;
	my ($Sys) = @_;
	
	$this->{'SORT'} = [];
	$this->{'SUBJECT'} = {};
	$this->{'RES'} = {};
	my @dirSet = ();
	
	my $base = $Sys->Get('BBSPATH') . '/' . $Sys->Get('BBS') . '/pool';
	my $num = 0;
	
	# ディレクトリ内一覧を取得
	if (opendir(my $fh, $base)) {
		@dirSet = readdir($fh);
		closedir($fh);
	}
	else {
		warn "can't open dir: $base";
		return;
	}
	
	foreach my $el (@dirSet) {
		if ($el =~ /^(.*)\.cgi$/ && open(my $fh, '<', "$base/$el")) {
			flock($fh, 2);
			my $id = $1;
			my $n = 1;
			my $first = <$fh>;
			$n++ while (<$fh>);
			close($fh);
			$first =~ s/[\r\n]+\z//;
			
			my @elem = split(/<>/, $first, -1);
			$this->{'SUBJECT'}->{$id} = $elem[4];
			$this->{'RES'}->{$id} = $n;
			push @{$this->{'SORT'}}, $id;
			$num++;
		}
	}
	$this->{'NUM'} = $num;
}

#============================================================================================================
#	Module END
#============================================================================================================
1;
