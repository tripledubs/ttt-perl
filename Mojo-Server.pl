#!/usr/bin/env perl
use Data::Dump 'dump';
use DBI;
use Game::Board;
use Mojolicious::Lite;
use YAML; # Like JSON but supports Perl Objects

my $dbfile='tictactoe.db';
my $dbh = DBI->connect("dbi:SQLite:dbname=$dbfile","","", {RaiseError=>1});

my %dispatch = (
	start => \&start,
	connect => \&connect,
	status => \&status,
	mode => \&mode,
	move => \&move,
	grid => \&grid,
);

sub getGameFromDB {
	my $game = shift;
	$game =~ s/[^\w\d ]/_/g; #Sanitize input

	my $sth = $dbh->prepare(
		'select * from games where gid = ?',
	);

	$sth->execute($game);
	my $row = $sth->fetchrow_hashref;
	return $row;
}

# Initiates a new game
sub start {
	my $c=shift;
	my $emptyGames = $dbh->selectall_arrayref(
		'select gid from games where status =0 limit 1',
	);
	if (!$emptyGames->[0]) {
		my $sth = $dbh->prepare('insert into games (status) values (0)');
		$sth->execute();
		return start($c);
	}
	return $emptyGames->[0][0];
}

sub status {
	my $c = shift;
	my $game = getGameFromDB($c->param('gameid'));
	return $game;
}

sub move {
	my $c = shift;
	my ($game, $player, $position) = 
		($c->param('gameid'),$c->param('playerid'),$c->param('position'));

	my $row = getGameFromDB($game);

	#Ensure proper player is trying to move;
	my $board = YAML::Load($row->{board});

	# playersTurn will return 0 or 1
	my $playerToMove = $board->playersTurn ? 'p2id' : 'p1id';

	if ($player ne $row->{$playerToMove}) {
		return "Not your turn";
	}

	my $moveStatus = $board->move($position);
	my $sth = $dbh->prepare(
		'update games set board = ? where gid = ?'
	);
	$sth->execute(YAML::Dump($board),$game);
	return $moveStatus;
}

# Join a player to a game and return a player id
sub connect {
	my $c = shift;
	my $game = $c->param('gameid');

	return "GameID not digits" if ($game !~ /^\d+/);

	# Did not supply gameid
	return "No gameID" if (!$game);

	my $sth = $dbh->prepare(
		'select * from games where gid = ? and status = 0',
	);
	my $rv = $sth->execute($game);

	# There was an error and the db query faulted
	if (!defined $rv) {
		return "DB Error";
	} 

	my $row = $sth->fetchrow_hashref;

	# Game is full or doesn't exist
	if (!defined $row->{status}) {
		return "That game is full or does not exist";
	}

	my $playerId = int(rand(30));

	# Define p2id if p1id is already defined
	my $player = defined($row->{p1id}) ? 'p2id' : 'p1id';

	$dbh->do("update games set $player = $playerId where gid = $game");

	# If we defined p2id, then start game
	if ($player eq 'p2id') {
		$dbh->do(
			"update games set status=1 where gid = $game"
		);
		my $board = Game::Board->new;
		my $sth = $dbh->prepare(
			'update games set board = ? where gid = ?'
		);
		$sth->execute(YAML::Dump($board),$game);
	}
	return $playerId;

}

# Because all have the same urls
# dispatch from here instead of proper
# mojolicious routes

get '/' => sub {
	my $c = shift;
	my $method = $c->param('method');
	my $return = $dispatch{$method}->($c);
	my $str = dump($return);
	$c->render(text => $str);
};

app->start;
