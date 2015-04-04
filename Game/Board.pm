#!/usr/bin/env perl
package Game::Board;
use Data::Dump;
use Carp;
use Moose;
use Moose::Util::TypeConstraints;
use Exporter 'import';
use IO::Socket qw(:crlf);
our @EXPORT_OK = qw(bitsOn);

my %validStates = (
   normal      => \&normalMove,
   suddenDeath => \&suddenDeathMove,
	 WinX => \&WinX,
	 WinO => \&WinO,
);

my $validStatesRE = join '|', keys %validStates;

my %moveReturnCodes = (
   squareFilledByOpponent => "Rejected: Square already filled by opponent",
   squareFilledByYou      => "Rejected: Square is already filled by yourself",
   squareNotAdjacent      => "Rejected: Square is not adjacent",
   squareNotValid => "Rejected: Square is not a valid number on the board",
   goodMove       => "You have moved to ",
   win            => 'Win',
   lose           => 'Lose',
);

subtype 'BoardValidState', as 'Str', where { /^$validStatesRE$/ };

has 'state' => (
   is      => 'rw',
   isa     => 'BoardValidState',
   default => 'normal',
);

has 'boardSize' => (
   is => 'ro',

   #isa      => 'Math::BigInt',
   required => 1,
   default  => sub { return 3 },
);

has 'winningPositions' => (
   is         => 'ro',
   isa        => 'ArrayRef',
   required   => 1,
   builder    => 'calcWinningPositions',
   auto_deref => 1,
);

has 'boards' => (
   is         => 'rw',
   isa        => 'ArrayRef',
   builder    => 'newBoards',
   auto_deref => 1,
);

has 'playersTurn' => (
   is      => 'rw',
   isa     => 'Bool',
   default => '0',
);

sub newBoards {
   return [ 0, 0 ];
}

sub clear {
   my $self = shift;
   $self->boards( [ 0, 0 ] );
}

# 0 1 2
# 3 4 5
# 6 7 8
sub translate {
   my ( $self, $move ) = @_;
   my $boardSize = $self->boardSize;
   return 1 << $boardSize**2 - 1 - $move;
}

sub calcWinningPositions {
   my $self      = shift;
   my $boardSize = $self->boardSize;
   if ( $boardSize < 2 ) {
      croak "Boardsize less than 2";
   }
   if ( $boardSize**2 > 31 ) {
      die "Cannot handle boards past 32 bits";
   }
   my @winningPositions;

   # First bit turned on
   # 3x3 BoardSize = 2**2 == 4
   my $vwin = 2**( $boardSize - 1 );

   # 100_100_100
   for ( 1 .. $boardSize - 1 ) {
      $vwin |= $vwin << $boardSize;
   }

   # That is our first vertical win
   push @winningPositions, $vwin;

   # Just keep shifting right 1, $boardSize times to get the other
   # vertical wins
   # 010_010_010
   # 001_001_001
   for ( 1 .. $boardSize - 1 ) {
      push @winningPositions, $vwin >> $_;
   }

   # The first horizonal wins will be 2**$boardSize -1
   # shift that pattern left $boardSize times

   # 000_000_111
   my $hwin = 2**$boardSize - 1;

   # 000_111_000
   # 111_000_000
   for ( 0 .. $boardSize - 1 ) {
      push @winningPositions, $hwin << ( $_ * $boardSize );
   }
   my $dwin;

   # First diagnol win is 2**0 + 2**($boardSize+1) + 2**(2*($boardSize+1))
   for ( my $x = 0 ; $x < $boardSize**2 ; $x += $boardSize + 1 ) {
      $dwin += 2**$x;
   }
   push @winningPositions, $dwin;

   $dwin = 0;
   for (
      my $x = $boardSize - 1 ;
      $x < ( ( $boardSize**2 ) - $boardSize + 1 ) ;
      $x += $boardSize - 1
     )
   {
      $dwin += 2**$x;
   }
   push @winningPositions, $dwin;
   $self->{winningPositions} = [@winningPositions];
}

sub WinX {
	my $self = shift;
	return "WinX";
}

sub WinO {
	my $self = shift;
	return "WinO";
}

sub printWins {
   my ($self) = shift;
   for ( @{ $self->{winningPositions} } ) {
      my $digits = $self->boardSize**2;
      printf( "%0${digits}b\n", $_ );
   }
}

sub move {
   my ( $self, @args ) = @_;
   my $r = $validStates{ $self->state }->( $self, @args );
   return $r;
}

sub checkWin {
   my ( $self, $board, $move ) = @_;
   return grep { ( $board & $_ ) == $_ } $self->winningPositions;
}

sub normalMove {
   my ( $self, $move ) = @_;
   if ( $move > $self->boardSize**2 + 1 || $move < 0 ) {
      return $moveReturnCodes{squareNotValid};
   }
   my $playerMove = $move;
   $move = $self->translate($move);

   my $boards         = $self->{boards};
   my $playersBoard   = $boards->[ $self->playersTurn ] + 0;
   my $opponentsBoard = $boards->[ !$self->playersTurn ];
   my $proposedBoard  = $playersBoard | $move | $opponentsBoard;

   # You are already in this square
   if ( ( $move & $playersBoard ) == $move ) {
      return $moveReturnCodes{squareFilledByYou};
   }
   elsif ( ( $move & $opponentsBoard ) == $move ) {
      return $moveReturnCodes{squareFilledByOpponent};
   }

   if (  ( ( $playersBoard & $move ) != 0 )
      || ( ( $opponentsBoard & $move ) != 0 ) )
   {
      return "Invalid: Square is taken.";
   }
   if ( grep { ( ( $playersBoard | $move ) & $_ ) == $_ }
      $self->winningPositions )
   {
      $boards->[ $self->playersTurn ] |= $move;
      return $moveReturnCodes{win};
   }

=cut
   elsif ( $proposedBoard == ( 2**( $self->boardSize**2 ) ) - 1 ) {
      $boards->[ $self->playersTurn ] |= $move;
      return "Game Over: Tie";
   }
=cut

   # In the 8th move, if no win is detected,
   #	the board changes state to suddenDeath
   elsif ( bitsOn( $proposedBoard | $move ) == $self->boardSize**2 - 1 ) {
      $boards->[ $self->playersTurn ] |= $move;
      $self->playersTurn( !$self->playersTurn );
      $self->state('suddenDeath');
      return $moveReturnCodes{goodMove} . "$playerMove";
   }
   else {
      $boards->[ $self->playersTurn ] |= $move;
      $self->playersTurn( !$self->playersTurn );
      return "You have moved to " . $playerMove;
   }
}

# Returns the open square
sub getOpenSquare {
   my ( $self, $move ) = @_;
   my $board = $self->getBoard;
   return ( ~$board & ( 1 << ( $self->boardSize )**2 ) - 1 );
}

# In sudden death
sub suddenDeathMove {
   my ( $self, $move ) = @_;

   my $validMoveFlag  = 0;
   my $boards         = $self->{boards};
   my $playersBoard   = $boards->[ $self->playersTurn ];
   my $opponentsBoard = $boards->[ !$self->playersTurn ];

   if ( $move > $self->boardSize**2 - 1 || $move < 0 ) {
      return $moveReturnCodes{squareNotValid};
   }
   elsif ( $move !~ /^\d+$/ ) {
      return $moveReturnCodes{squareNotValid};
   }

   if (
      ( $self->translate($move) & $opponentsBoard ) == $self->translate($move) )
   {
      return $moveReturnCodes{squareFilledByOpponent};
   }

   ## Only works for 3x3
   # The key is the token
   # the value is an array of squares that the token can move to
   my $validMoves = {
      0b100000000 => [ 1, 3, 4 ],
      0b010000000 => [ 0, 2, 4 ],
      0b001000000 => [ 1, 4, 5 ],
      0b000100000 => [ 0, 4, 6 ],
      0b000010000 => [ 0, 1, 2, 3, 5, 6, 7, 8 ],
      0b000001000 => [ 2, 4, 8 ],
      0b000000100 => [ 3, 4, 7 ],
      0b000000010 => [ 4, 6, 8 ],
      0b000000001 => [ 4, 5, 7 ],
   };

   # Player chooses the token to move. It must be adjacent
   # to the empty square. Once moved, the moved bit must be turned off
   # and the empty square is turned on for the players board.

   my $openSquare           = $self->getOpenSquare;
   my @adjacentNodesToEmpty = @{ $validMoves->{$openSquare} };

   croak "No adjacent moves found!" if ( !@adjacentNodesToEmpty );

   # If the empty square is not one of the valid destinations for my selection
   # return invalid
   if ( !( grep { $move == $_ } @adjacentNodesToEmpty ) ) {
      return $moveReturnCodes{squareNotAdjacent};
   }
   else {
      # Turn on open square bit
      $self->boards->[ $self->playersTurn ] ^= $openSquare;

      # Turn off the bit that player chose
      $self->boards->[ $self->playersTurn ] &= ~$self->translate($move);


      if ( grep { ($self->boards->[ $self->playersTurn ] & $_) == $_ }
         @{$self->winningPositions()} )
      {
				$self->state($self->playersTurn ? 'WinX' : 'WinO');
         return "Win";
      }
      else {
				$self->playersTurn( !$self->playersTurn );
         return "You have moved to $move";
      }
   }
}

# Finds out whether system is 32 or 64 bit
sub maxBitSize {
   if ( eval { pack( 'Q', 65 ) } ) {
      return "64";
   }
   else {
      return "32";
   }
}

sub getBoard {
   my $self   = shift;
   my @boards = @{ $self->boards };
   return $boards[0] | $boards[1];
}

# Returns number of 1s in a bit string
sub bitsOn {
   my $bits = shift;
   return 0 if ( $bits == 0 );
   my $count = $bits & 1 ? 1 : 0;
   return $count += ( bitsOn( $bits >> 1 ) );
}

# Prints in BitStrings
sub printBoard {
   my $self   = shift;
   my $digits = $self->boardSize**2;
   my @boards = @{ $self->boards };
   my $string = sprintf( "Player 1: %0${digits}b$CRLF", $boards[0] );
   $string .= sprintf( "Player 2: %0${digits}b$CRLF", $boards[1] );
   $string .= sprintf( "Board:    %0${digits}b$CRLF", $boards[0] | $boards[1] );
   return $string;
}

# Prints normally, human readable
sub prettyBoard {
   my ($self) = @_;
   my @boards = $self->boards;
   my $board1 = $boards[0];
   my $board2 = $boards[1];
   my $string;
   my $column = 1;
   for ( reverse( 0 .. $self->boardSize**2 - 1 ) ) {
      if ( $board1 & 1 << $_ ) {
         $string .= "X ";
      }
      elsif ( $board2 & 1 << $_ ) {
         $string .= "O ";
      }
      else {
         $string .= $column - 1 . " ";
      }
      if ( $column % $self->boardSize == 0 ) {
         $string .= $CRLF;
      }
      $column++;
   }
   return $string . "$CRLF";
}

__PACKAGE__->meta->make_immutable;

