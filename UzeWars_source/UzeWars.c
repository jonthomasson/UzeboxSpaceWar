/*
 *  Uzebox(tm) VectorDemo
 *  Copyright (C) 2009  Alec Bourque
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

/*
 * This program demonstrate mode 6, a 1-bit ramtiles mode that allows 256 tiles.
 */

#include <stdbool.h>
#include <avr/io.h>
#include <stdlib.h>
#include <avr/pgmspace.h>
#include <uzebox.h>
#include <videoMode6/videoMode6.h>
// Music/sfx
#include "data/patches.inc"

#include "StringObjectsFonts.h"

#define MAX_ROUNDS	3

#define MAX_OBJS 30
#define OBJ_LEN 12

#define OBJ_FIRST_SHIP	61
#define OBJ_LAST_SHIP	65

#define OBJ_MIN_ENEMY     3
#define OBJ_MAX_ENEMY     9

#define OBJ_BULLET        0
#define OBJ_SHIP          61
#define OBJ_MIS_BLAST     2



#define OBJ_ROCK_1        3
#define OBJ_ROCK_2        4
#define OBJ_ROCK_3        5
#define OBJ_GROUND_FLAT   6
#define OBJ_GROUND_PEAK   7
#define OBJ_BOUDLER       8
#define OBJ_LANDING_PAD   9
#define OBJ_BROKEN_SHIP_1 10
#define OBJ_BROKEN_SHIP_2 11
#define OBJ_BROKEN_SHIP_3 12
#define OBJ_BROKEN_SHIP_4 13
#define OBJ_PARTICLE      14
#define OBJ_SAFE_SHIP     15
#define OBJ_SIGHT         16
#define OBJ_MC_GROUND_1   17

// type declarations

// Each significant game entity has a FSM to simplify and centralise game logic
typedef enum {
	title, playRound, beginRound, endRound, dead, paused, gameOver, chooseShip
} GameState;

typedef enum {
	playerAlive, playerDead
} PlayerState;


typedef struct {
	ObjectDescStruct *Ship;	    //pointer to ship object
	PlayerState State;
	uint16_t Score;
	int16_t	 dXSub;
	int16_t	 dYSub;
	uint8_t  SpawnX;
	uint8_t  SpawnY;
	uint8_t  T_Hi;
	uint8_t  RoundsWon;
	uint8_t  ShipType;
} player;





// C/ASM shared globals for screen/objects

unsigned char ObjectStore[MAX_OBJS][OBJ_LEN] __attribute__ ((section (".objectstore")));
unsigned char ramTiles[256*8]  __attribute__ ((section (".ramtiles")));
unsigned char vram[32*28] __attribute__ ((section (".vram")));
unsigned char trigtable[64] __attribute__ ((section (".trigtable")));

extern volatile uint8_t renderCount;
extern volatile uint8_t ClearVramFlags;

// Screen management routines


extern void DefaultCallback(void);
extern uint8_t OutStringXYProgmemFastC(uint8_t X, uint8_t Y, const char *StringAddress);
extern void OutCharXYFastC(uint8_t X, uint8_t Y, uint8_t CharNum);
extern void ClearBufferLastLine(void);
extern void ClearBufferLastLineTileOnly(void);
extern void Mode7PutCharFastC(uint8_t x, uint8_t y, uint8_t CharNo);
extern void DrawPolarObjectFastC(uint8_t x, uint8_t y, uint8_t CharNo, uint8_t Theta, uint8_t scale);


// Geometry routines

extern int8_t SinMulFastC(int8_t angle, uint8_t distance);
extern int8_t CosMulFastC(int8_t angle, uint8_t distance);
extern int8_t SinFastC(int8_t angle);
extern int8_t CosFastC(int8_t angle);
PointStruct PolarToPoint(PointStruct P1, PolarPointStruct PP1);
uint8_t CheckCollision(ObjectDescStruct *Ob1, ObjectDescStruct *Ob2);
uint8_t PointInTriangle(PointStruct P1, PointStruct P2, PointStruct P3, PointStruct PX);


// Sound effects indexes into patches struct in flash and their volumes
#define SFX_PLAYER_SHOOT			0
#define SFX_VOL_PLAYER_SHOOT		0xf0
#define SFX_PLAYER_HIT				1
#define SFX_VOL_PLAYER_HIT			0xa0
#define SFX_ALIEN_MOVE_A			2
#define SFX_VOL_ALIEN_MOVE_A		0x20
#define SFX_ALIEN_MOVE_B			3
#define SFX_VOL_ALIEN_MOVE_B		0x20
#define SFX_ALIEN_HIT				4
#define SFX_VOL_ALIEN_HIT			0x60
#define SFX_UFO						5
#define SFX_VOL_UFO					0x50

//player constants
#define PLAYER1_START_LOC_X 		18
#define PLAYER1_START_LOC_Y			188
#define PLAYER1_T_HI				60
#define PLAYER2_START_LOC_X 		238
#define PLAYER2_START_LOC_Y			188
#define PLAYER2_T_HI				190
#define PLAYER_START_LIVES			3



// Object management routines

void ClearObjectStore(void);
uint8_t GetFreeObject(void);
uint8_t NewShip(player *p);
uint8_t NewBullet(uint8_t X, uint8_t Y, int8_t dX, int8_t dY, uint8_t L, uint8_t owner);
uint8_t NewParticle(uint8_t X, uint8_t Y, int8_t dX, int8_t dY);

uint8_t NewObject(uint8_t Type, uint8_t X, uint8_t Y, uint8_t T, int8_t dX, int8_t dY, int8_t dT, uint8_t Scale, uint8_t Life);

// Game logic routines

void InitRound(u8 round);

void ScrollText(void);
void ProcessInput(player *p, uint16_t buttons, uint8_t owner);
void MoveObjects();
void DrawObjects(void);
void CollisionDetection(void);
void DrawPlayField(void);
uint8_t GetNumberObject(uint16_t num);
void TitleScreen(void);
void InitPlayers(void);
void playRoundBeginMessage(u8 round);
void playRoundEndMessage(u8 round);
void playGameOverMessage(void);
void HandleSync(void);
void ChoosePlayerShips(void);

/****************************************
*			File-level variables		*
****************************************/

GameState gameState;
player player1, player2;
uint16_t roundTimer = 0;


void PlayMessage(uint8_t MsgNum){
	uint16_t i = 0;
	uint8_t j = 0;
	uint8_t c;
	uint8_t x = 0;
	uint8_t y = 0;
	uint8_t p0 = 0;
	uint8_t p1 = 0;

	while (j != MsgNum) {
		c = pgm_read_byte(&MessageText[i]);
		if (c == 0xFF) j++;
		i++;
	}


	SetRenderingParameters((21), (224));
	ClearObjectStore();
	ClearVramFlags = ClearFrameYes;

	while(renderCount != 0);			// GetVSync doesn't always work use my own counter

	ClearVsyncFlag();

	ClearBufferLastLine();
	ClearVramFlags = ClearFrameNo;

	do {

		c = pgm_read_byte(&MessageText[i]);
		i++;

		switch (c) {
			case 0xFF : break;
			case 0xFE : {
				x = pgm_read_byte(&MessageText[i]);
				i++;
				y = pgm_read_byte(&MessageText[i]);
				i++;
				break;
			}
			case 0xFD : {
				p0 = pgm_read_byte(&MessageText[i]);
				i++;
				break;
			}
			case 0xFC : {
				p1 = pgm_read_byte(&MessageText[i]);
				i++;
				break;
			}
			default : {
				DrawPolarObjectFastC(x,  y, c, 66, 255);

				p0 = p1;
				x+=12;
			}
		}

		renderCount = 0;
		while (renderCount < p0);

	} while ((ReadJoypad(0) == 0) && (c != 0xFF));

//	while (ReadJoypad(0) == 0);
//	while (ReadJoypad(0) != 0);


}



void GameOver(void){


SetRenderingParameters((21), (224));
ClearObjectStore();
ClearVramFlags = ClearFrameYes;

while(renderCount != 0);			// GetVSync doesn't always work use my own counter

ClearVsyncFlag();

ClearBufferLastLine();
ClearVramFlags = ClearFrameNo;

OutStringXYProgmemFastC(12,13,strptr(str_GameOver));

while (ReadJoypad(0) == 0);

}

void InitRound(u8 round) {

		player1.Score = 0;
		player2.Score = 0;

		if(round == 0){
			player1.RoundsWon = 0;
			player2.RoundsWon = 0;

			player1.ShipType = 0;
			player2.ShipType = 0;
		}

		InitPlayers();

		roundTimer = 900;


}

void InitPlayers(void){
	ClearObjectStore();

	player1.Ship = NULL;
	player1.SpawnX = PLAYER1_START_LOC_X;
	player1.SpawnY = PLAYER1_START_LOC_Y;
	player1.T_Hi = PLAYER1_T_HI;
	//player1.Lives = PLAYER_START_LIVES;

	player1.State = playerAlive;

	player2.Ship = NULL;
	player2.SpawnX = PLAYER2_START_LOC_X;
	player2.SpawnY = PLAYER2_START_LOC_Y;
	player2.T_Hi = PLAYER2_T_HI;
	//player2.Lives = PLAYER_START_LIVES;

	player2.State = playerAlive;
//	}


//	if (player1.Ship == NULL) {
	player1.Ship = ((ObjectDescStruct*)&ObjectStore[(int)NewShip(&player1)]);
	player1.dXSub = 0;
	player1.dYSub = 0;
	//player1.Ship->Type = OBJ_SHIP;
//	}

//	if (player2.Ship == NULL) {
	player2.Ship = ((ObjectDescStruct*)&ObjectStore[(int)NewShip(&player2)]);
	player2.dXSub = 0;
	player2.dYSub = 0;
	//player2.Ship->Type = OBJ_SHIP;
//	}
}
void TitleScreen(void){
	//setup title screen


		DrawPolarObjectFastC(40,  90, 7, 66, 255);//u
	DrawPolarObjectFastC(70,  90, 6, 66, 255);//z
	DrawPolarObjectFastC(103,  90, 8, 66, 255);//e
	DrawPolarObjectFastC(130,  90, 9, 66, 255);//w
	DrawPolarObjectFastC(157,  90, 16, 66, 255);//a
	DrawPolarObjectFastC(184,  90, 59, 66, 255);//r
	DrawPolarObjectFastC(210,  90, 60, 66, 255);//s

	DrawPolarObjectFastC(40,  110, 34, 66, 200);//b
	DrawPolarObjectFastC(50,  110, 33, 66, 200);//a
	DrawPolarObjectFastC(60,  110, 52, 66, 200);//t
	DrawPolarObjectFastC(70,  110, 52, 66, 200);//t
	DrawPolarObjectFastC(80,  110, 44, 66, 200);//l
	DrawPolarObjectFastC(90,  110, 37, 66, 200);//e

	DrawPolarObjectFastC(110,  110, 38, 66, 200);//f
	DrawPolarObjectFastC(120,  110, 47, 66, 200);//o
	DrawPolarObjectFastC(130,  110, 50, 66, 200);//r

	DrawPolarObjectFastC(150,  110, 51, 66, 200);//s
	DrawPolarObjectFastC(160,  110, 48, 66, 200);//p
	DrawPolarObjectFastC(170,  110, 33, 66, 200);//a
	DrawPolarObjectFastC(180,  110, 35, 66, 200);//c
	DrawPolarObjectFastC(190,  110, 37, 66, 200);//e

	DrawPolarObjectFastC(70,  130, 48, 66, 200);//p
	DrawPolarObjectFastC(80,  130, 50, 66, 200);//r
	DrawPolarObjectFastC(90,  130, 37, 66, 200);//e
	DrawPolarObjectFastC(100,  130, 51, 66, 200);//s
	DrawPolarObjectFastC(110,  130, 51, 66, 200);//s

	DrawPolarObjectFastC(130,  130, 51, 66, 200);//s
	DrawPolarObjectFastC(140,  130, 52, 66, 200);//t
	DrawPolarObjectFastC(150,  130, 33, 66, 200);//a
	DrawPolarObjectFastC(160,  130, 50, 66, 200);//r
	DrawPolarObjectFastC(170,  130, 52, 66, 200);//t

	//planets
	DrawPolarObjectFastC(30,  30, 5, 66, 255);//planet 1
	DrawPolarObjectFastC(40,  40, 5, 66, 50);//planet 1

	DrawPolarObjectFastC(100,  40, 5, 66, 100);//planet 1
//	DrawPolarObjectFastC(30,  30, 5, 66, 255);//planet 1
//	DrawPolarObjectFastC(30,  30, 5, 66, 255);//planet 1
//	DrawPolarObjectFastC(30,  30, 5, 66, 255);//planet 1


	//press start text
	//PlayMessage(0); //PRESS START
}

void DrawPlayField(void){
	//need to draw score boards, timer etc
	DrawPolarObjectFastC(50,  20, 4, 66, 255); //p1 scoreboard

	DrawPolarObjectFastC(160,  20, 4, 66, 255); //p2 scoreboard

	DrawPolarObjectFastC(0,  25, 3, 66, 255); //separator line
	DrawPolarObjectFastC(45,  25, 3, 66, 255); //separator line
	DrawPolarObjectFastC(90,  25, 3, 66, 255); //separator line
	DrawPolarObjectFastC(135,  25, 3, 66, 255); //separator line
	DrawPolarObjectFastC(180,  25, 3, 66, 255); //separator line
	DrawPolarObjectFastC(220,  25, 3, 66, 255); //separator line

	//update scores
	//we'll have 2 objects for each player, to hold their score

	//player 1 score
	DrawPolarObjectFastC(58,  17, GetNumberObject(player1.Score / 10) , 66, 255);
	DrawPolarObjectFastC(68,  17, GetNumberObject(player1.Score % 10) , 66, 255);

	//player 2 score
	DrawPolarObjectFastC(167,  17, GetNumberObject(player2.Score / 10) , 66, 255);
	DrawPolarObjectFastC(177,  17, GetNumberObject(player2.Score % 10) , 66, 255);

	//set timer
	uint16_t sec = roundTimer / 15;

	DrawPolarObjectFastC(115,  17, GetNumberObject(sec / 10) , 66, 255);
	DrawPolarObjectFastC(125,  17, GetNumberObject(sec % 10) , 66, 255);
}

uint8_t GetNumberObject(uint16_t num){

	uint8_t type;

	switch(num) {
		case 0 : {
			type = 17;
			break;
		}
		case 1 : {
			type = 18;
			break;
		}
		case 2 : {
			type = 19;
			break;
		}
		case 3 : {
			type = 20;
			break;
		}
		case 4 : {
			type = 21;
			break;
		}
		case 5 : {
			type = 22;
			break;
		}
		case 6 : {
			type = 23;
			break;
		}
		case 7 : {
			type = 24;
			break;
		}
		case 8 : {
			type = 25;
			break;
		}
		case 9 : {
			type = 26;
			break;
		}
		default : {
			type = 17;
		}

	}

	return type;
}

void playRoundEndMessage(u8 round){
	//get players scores and see who won
	u8 playerWhoWon = 0;

	if(player1.Score > player2.Score){
		playerWhoWon = 1;
		player1.RoundsWon++;
	}
	if(player2.Score > player1.Score){
		playerWhoWon = 2;
		player2.RoundsWon++;
	}

	DrawPolarObjectFastC(60,  90, 50, 66, 200);//r
	DrawPolarObjectFastC(70,  90, 47, 66, 200);//o
	DrawPolarObjectFastC(80,  90, 53, 66, 200);//u
	DrawPolarObjectFastC(90,  90, 46, 66, 200);//n
	DrawPolarObjectFastC(100,  90, 36, 66, 200);//d

	DrawPolarObjectFastC(120,  90, GetNumberObject(round) , 66, 255);

	DrawPolarObjectFastC(140,  90, 55, 66, 200);//w
	DrawPolarObjectFastC(150,  90, 41, 66, 200);//i
	DrawPolarObjectFastC(160,  90, 46, 66, 200);//n
	DrawPolarObjectFastC(170,  90, 46, 66, 200);//n
	DrawPolarObjectFastC(180,  90, 37, 66, 200);//e
	DrawPolarObjectFastC(190,  90, 50, 66, 200);//r

	if(playerWhoWon == 0){
			DrawPolarObjectFastC(100,  120, 52, 66, 200);//t
			DrawPolarObjectFastC(110,  120, 41, 66, 200);//i
			DrawPolarObjectFastC(120,  120, 37, 66, 200);//e

		}else{
			DrawPolarObjectFastC(100,  120, 48, 66, 200);//p
		DrawPolarObjectFastC(110,  120, 44, 66, 200);//l
		DrawPolarObjectFastC(120,  120, 33, 66, 200);//a
		DrawPolarObjectFastC(130,  120, 57, 66, 200);//y
		DrawPolarObjectFastC(140,  120, 37, 66, 200);//e
		DrawPolarObjectFastC(150,  120, 50, 66, 200);//r


		DrawPolarObjectFastC(170,  120, GetNumberObject(playerWhoWon) , 66, 255);
		}

}

void playRoundBeginMessage(u8 round){



	DrawPolarObjectFastC(100,  110, 50, 66, 200);//r
	DrawPolarObjectFastC(110,  110, 47, 66, 200);//o
	DrawPolarObjectFastC(120,  110, 53, 66, 200);//u
	DrawPolarObjectFastC(130,  110, 46, 66, 200);//n
	DrawPolarObjectFastC(140,  110, 36, 66, 200);//d

	DrawPolarObjectFastC(160,  110, GetNumberObject(round) , 66, 255);


}

void playGameOverMessage(void){
	//get players scores and see who won
				u8 theWinner = 0;

				if(player1.RoundsWon > player2.RoundsWon){
					theWinner = 1;

				}
				if(player2.RoundsWon > player1.RoundsWon){
					theWinner = 2;

				}

	DrawPolarObjectFastC(100,  110, 39, 66, 200);//g
	DrawPolarObjectFastC(110,  110, 33, 66, 200);//a
	DrawPolarObjectFastC(120,  110, 45, 66, 200);//m
	DrawPolarObjectFastC(130,  110, 37, 66, 200);//e

	DrawPolarObjectFastC(140,  110, 47, 66, 200);//o
	DrawPolarObjectFastC(150,  110, 54, 66, 200);//v
	DrawPolarObjectFastC(160,  110, 37, 66, 200);//e
	DrawPolarObjectFastC(170,  110, 50, 66, 200);//r

	DrawPolarObjectFastC(70,  140, 55, 66, 200);//w
	DrawPolarObjectFastC(80,  140, 41, 66, 200);//i
	DrawPolarObjectFastC(90,  140, 46, 66, 200);//n
	DrawPolarObjectFastC(100,  140, 46, 66, 200);//n
	DrawPolarObjectFastC(110,  140, 37, 66, 200);//e
	DrawPolarObjectFastC(120,  140, 50, 66, 200);//r


	if(theWinner == 0){
			DrawPolarObjectFastC(140,  140, 52, 66, 200);//t
			DrawPolarObjectFastC(150,  140, 41, 66, 200);//i
			DrawPolarObjectFastC(160,  140, 37, 66, 200);//e

	}else{
		DrawPolarObjectFastC(140,  140, 48, 66, 200);//p
		DrawPolarObjectFastC(150,  140, 44, 66, 200);//l
		DrawPolarObjectFastC(160,  140, 33, 66, 200);//a
		DrawPolarObjectFastC(170,  140, 57, 66, 200);//y
		DrawPolarObjectFastC(180,  140, 37, 66, 200);//e
		DrawPolarObjectFastC(190,  140, 50, 66, 200);//r


		DrawPolarObjectFastC(210,  140, GetNumberObject(theWinner) , 66, 255);
		}


}

void HandleSync(void){
	ClearVramFlags = ClearFrameYes;

		while(renderCount != 0);			// GetVSync doesn't always work use my own counter
		ClearVsyncFlag();

		ClearBufferLastLine();
		ClearVramFlags = ClearFrameNo;
}

void ChoosePlayerShips(void){
	//have players select their ship
	uint16_t buttons;
	u8 currentObj = OBJ_FIRST_SHIP;

	while(player1.ShipType == 0 || player2.ShipType == 0){
	HandleSync();

	DrawPolarObjectFastC(10,  40, 48, 66, 200);//p
	DrawPolarObjectFastC(20,  40, 44, 66, 200);//l
	DrawPolarObjectFastC(30,  40, 33, 66, 200);//a
	DrawPolarObjectFastC(40,  40, 57, 66, 200);//y
	DrawPolarObjectFastC(50,  40, 37, 66, 200);//e
	DrawPolarObjectFastC(60,  40, 50, 66, 200);//r

	if(player1.ShipType == 0){
		//choose player 1 first
		DrawPolarObjectFastC(80,  40, 18, 66, 200);//1
	}else if(player2.ShipType == 0){
		DrawPolarObjectFastC(80,  40, 19, 66, 200);//2
	}

	DrawPolarObjectFastC(100,  40, 53, 66, 200);//u
	DrawPolarObjectFastC(110,  40, 51, 66, 200);//s
	DrawPolarObjectFastC(120,  40, 37, 66, 200);//e

	DrawPolarObjectFastC(140,  40, 53, 66, 200);//u
	DrawPolarObjectFastC(150,  40, 48, 66, 200);//p

	DrawPolarObjectFastC(170,  40, 33, 66, 200);//a
	DrawPolarObjectFastC(180,  40, 46, 66, 200);//n
	DrawPolarObjectFastC(190,  40, 36, 66, 200);//d

	DrawPolarObjectFastC(210,  40, 36, 66, 200);//d
	DrawPolarObjectFastC(220,  40, 47, 66, 200);//o
	DrawPolarObjectFastC(230,  40, 55, 66, 200);//w
	DrawPolarObjectFastC(240,  40, 46, 66, 200);//n

	DrawPolarObjectFastC(10,  60, 34, 66, 200);//b
	DrawPolarObjectFastC(20,  60, 53, 66, 200);//u
	DrawPolarObjectFastC(30,  60, 52, 66, 200);//t
	DrawPolarObjectFastC(40,  60, 52, 66, 200);//t
	DrawPolarObjectFastC(50,  60, 47, 66, 200);//o
	DrawPolarObjectFastC(60,  60, 46, 66, 200);//n

	DrawPolarObjectFastC(80,  60, 52, 66, 200);//t
	DrawPolarObjectFastC(90,  60, 47, 66, 200);//o

	DrawPolarObjectFastC(110,  60, 51, 66, 200);//s
	DrawPolarObjectFastC(120,  60, 37, 66, 200);//e
	DrawPolarObjectFastC(130,  60, 44, 66, 200);//l
	DrawPolarObjectFastC(140,  60, 37, 66, 200);//e
	DrawPolarObjectFastC(150,  60, 35, 66, 200);//c
	DrawPolarObjectFastC(160,  60, 52, 66, 200);//t

	DrawPolarObjectFastC(180,  60, 51, 66, 200);//s
	DrawPolarObjectFastC(190,  60, 40, 66, 200);//h
	DrawPolarObjectFastC(200,  60, 41, 66, 200);//i
	DrawPolarObjectFastC(210,  60, 48, 66, 200);//p
	DrawPolarObjectFastC(220,  60, 28, 66, 200);//.

	DrawPolarObjectFastC(10,  80, 48, 66, 200);//p
	DrawPolarObjectFastC(20,  80, 50, 66, 200);//r
	DrawPolarObjectFastC(30,  80, 37, 66, 200);//e
	DrawPolarObjectFastC(40,  80, 51, 66, 200);//s
	DrawPolarObjectFastC(50,  80, 51, 66, 200);//s

	DrawPolarObjectFastC(70,  80, 51, 66, 200);//s
	DrawPolarObjectFastC(80,  80, 37, 66, 200);//e
	DrawPolarObjectFastC(90,  80, 44, 66, 200);//l
	DrawPolarObjectFastC(100,  80, 37, 66, 200);//e
	DrawPolarObjectFastC(110,  80, 35, 66, 200);//c
	DrawPolarObjectFastC(120,  80, 52, 66, 200);//t

	DrawPolarObjectFastC(140,  80, 55, 66, 200);//w
	DrawPolarObjectFastC(150,  80, 40, 66, 200);//h
	DrawPolarObjectFastC(160,  80, 37, 66, 200);//e
	DrawPolarObjectFastC(170,  80, 46, 66, 200);//n

	DrawPolarObjectFastC(190,  80, 36, 66, 200);//d
	DrawPolarObjectFastC(200,  80, 47, 66, 200);//o
	DrawPolarObjectFastC(210,  80, 46, 66, 200);//n
	DrawPolarObjectFastC(220,  80, 37, 66, 200);//e
	DrawPolarObjectFastC(230,  80, 28, 66, 200);//.

	//now get user input for ship type
	if(player1.ShipType == 0){
		//choose player 1 first
		buttons = ReadJoypad(0);


	}else if(player2.ShipType == 0){
		buttons = ReadJoypad(1);
	}

	if(buttons & BTN_UP){
		currentObj++;
		if(currentObj > OBJ_LAST_SHIP){
			currentObj = OBJ_FIRST_SHIP;
		}
	}else if(buttons & BTN_DOWN){
		currentObj--;
		if(currentObj < OBJ_FIRST_SHIP){
			currentObj = OBJ_LAST_SHIP;
		}
	}else if(buttons & BTN_SELECT){
		//player has made a selection
		if(player1.ShipType == 0){
			player1.ShipType = currentObj;
			player1.Ship->Type = currentObj;
			currentObj = OBJ_FIRST_SHIP;
		}else if(player2.ShipType == 0){
			player2.ShipType = currentObj;
			player2.Ship->Type = currentObj;
		}
	}
	DrawPolarObjectFastC(100,  150, currentObj, 66, 255);

	while(!GetVsyncFlag());
		ClearVsyncFlag();
	}


}

int main(){

srand(123);

InitMusicPlayer(patches);

SetHsyncCallback(&DefaultCallback);

gameState = title;

SetRenderingParameters((21), (224));

//HandleSync();

//ClearObjectStore();


//player 1 buttons
	u16 btnPrevP1 = 0;			// Previous buttons that were held
	u16 btnHeldP1 = 0;    		// Buttons that are held right now
	u16 btnPressedP1 = 0;  		// Buttons that were pressed this frame
	u16 btnReleasedP1 = 0;		// Buttons that were released this frame

	//player 2 buttons

	u16 btnPrevP2 = 0;			// Previous buttons that were held
	u16 btnHeldP2 = 0;    		// Buttons that are held right now
	u16 btnPressedP2 = 0;  		// Buttons that were pressed this frame
	u16 btnReleasedP2 = 0;		// Buttons that were released this frame

u8 round = 0, flashStartTimer = 0, playerDeadTimer = 0, roundBeginStartTimer = 0, roundEndStartTimer = 0, gameOverTimer = 0;
while(1){

	//HandleSync();

	//player 1 buttons
				btnHeldP1 = ReadJoypad(0);
				btnPressedP1 = btnHeldP1&(btnHeldP1^btnPrevP1);
	        	btnReleasedP1 = btnPrevP1&(btnHeldP1^btnPrevP1);
				btnPrevP1 = btnHeldP1;

				//player 2 buttons
				btnHeldP2 = ReadJoypad(1);
				btnPressedP2 = btnHeldP2&(btnHeldP2^btnPrevP2);
				btnReleasedP2 = btnPrevP2&(btnHeldP2^btnPrevP2);
				btnPrevP2 = btnHeldP2;



//	DrawObjects();
//
//
//	while(!GetVsyncFlag());
//	ClearVsyncFlag();

	switch (gameState) {
					case title:
						if ((btnPressedP1&BTN_START) || (btnPressedP2&BTN_START)) {


							gameState = chooseShip;
							InitRound(round);
							round++;
						} else {
							HandleSync();
								//if (--flashStartTimer == 0) {
									TitleScreen();
									while(!GetVsyncFlag()); //may have to remove later...
									ClearVsyncFlag();//may have to remove later...
									//flashStartTimer = 60>>1;
								//}
						}
//
					break;

					case chooseShip:
						//have players choose their ships
						//HandleSync();

						ChoosePlayerShips();

						if(player1.ShipType != 0 && player2.ShipType != 0){
							roundBeginStartTimer = 240;

							gameState = beginRound;

						}
					break;

					case beginRound:
						if(--roundBeginStartTimer == 0){
							//play round

							gameState = playRound;
						}else{
							HandleSync();
							//play message
							playRoundBeginMessage(round);

						}

						break;

					case endRound:
						//show winner of round
						//start a timer to show winner of round
						if(--roundEndStartTimer == 0){
							//play round
							//check if last round over
							if(round == MAX_ROUNDS){

								gameOverTimer = 240;
								gameState = gameOver;
								round = 0;
							}else{
								roundBeginStartTimer = 240;
								gameState = beginRound;
								InitRound(round);
								round++;
							}
						}else{
							HandleSync();
							//play message
							playRoundEndMessage(round);

						}


					break;

					case playRound:

						if (--roundTimer <= 0) {
							roundEndStartTimer = 240;
							gameState = endRound;

						}

						HandleSync();

						DrawObjects();

						//draw field of play
						DrawPlayField();


							while(!GetVsyncFlag());
							ClearVsyncFlag();

						if (player1.State == playerDead || player2.State == playerDead) {
							InitPlayers();

							break;
						}


						//eventually we'll need to check player life but this is for testing
						ProcessInput(&player1, btnHeldP1, 1);
						//player1.State = playerAlive;

						 ProcessInput(&player2, btnHeldP2, 2);
						//player1.State = playerAlive;

						CollisionDetection();
						MoveObjects();
					break;

					case dead:
						// Ignore pause game while dead
						if (--playerDeadTimer == 0) {
							gameState = title;
						}
					break;

					case paused:

					break;

					case gameOver:
						//show winner of game
						//show a timer to show winner of game
						if(--gameOverTimer == 0){

							gameState = title; //will change eventually
						}else{
							HandleSync();
							//show game over message
							playGameOverMessage();
						}
						break;

	}


}

}
void ProcessInput(player *p, uint16_t buttons, uint8_t owner) {

static uint8_t BulletCountDown = 0;

uint8_t RandThrustAngle;



if(buttons & BTN_RIGHT) {
	p->Ship->T_Hi = p->Ship->T_Hi - 3;
}

if(buttons & BTN_LEFT)  {
	p->Ship->T_Hi = p->Ship->T_Hi + 3;
}

if((buttons & BTN_UP) || (buttons & BTN_B))    {
	p->dXSub = p->dXSub + (SinFastC(p->Ship->T_Hi)<<2);
	p->dYSub = p->dYSub +  + (CosFastC(p->Ship->T_Hi)<<2);

	if(p->dXSub >  0x3600) p->dXSub =  0x3600;
	if(p->dXSub < -0x3600) p->dXSub = -0x3600;

	if(p->dYSub >  0x3600) p->dYSub =  0x3600;
	if(p->dYSub < -0x3600) p->dYSub = -0x3600;


	p->Ship->dX = p->dXSub>>8;
	p->Ship->dY = p->dYSub>>8;
	
//	RandThrustAngle = 148 - rand()%40;
//	NewParticle(p->Ship->X_Hi + SinMulFastC((p->Ship->T_Hi + 128),10),
//			p->Ship->Y_Hi + CosMulFastC((p->Ship->T_Hi + 128),10),
//			p->Ship->dX   + SinMulFastC((p->Ship->T_Hi + RandThrustAngle),15),
//			p->Ship->dY   + CosMulFastC((p->Ship->T_Hi + RandThrustAngle),15));
}

if((buttons & BTN_A) && (BulletCountDown == 0))    {
	//play nifty bullet shooting sound
	TriggerFx(SFX_PLAYER_SHOOT, SFX_VOL_PLAYER_SHOOT, true);
	TriggerNote(1,SFX_PLAYER_SHOOT, 70, SFX_VOL_PLAYER_SHOOT);



	NewBullet(p->Ship->X_Hi, p->Ship->Y_Hi, p->Ship->dX + SinMulFastC(p->Ship->T_Hi,64), p->Ship->dY + CosMulFastC(p->Ship->T_Hi,64), 80, owner);
	BulletCountDown = 10;
}

if(BulletCountDown != 0) {
	BulletCountDown--;
}

}


void ScrollText()
{
uint8_t subcount = 0;
int16_t yoff_start = 225;
int16_t yoff_end;

uint8_t i, j;

ClearBuffer();

SetRenderingParameters((144+21), (224-144));
do {
	while(!GetVsyncFlag());

	ClearVramFlags = ClearFrameNo;
	ClearBufferLastLineTileOnly();

	yoff_end = yoff_start;

	for(i = 0; i < 20; i++) {

		for (j = 0; j < 12; j++) {

			if ((yoff_end >=0 ) & (yoff_end < 224)) {
				Mode7PutCharFastC((j*21), yoff_end, pgm_read_byte(&CrawlText[i][j]));
			}
		}

		yoff_end = yoff_end + 24;
	}

	if (subcount == 0) yoff_start--;
	subcount++;
	if (subcount > 1) subcount = 0;

	ClearVramFlags = ClrRamTileOlny | ClearFrameYes;  //11 = ram tile only.
    ClearVsyncFlag();

} while ((yoff_end > 0) && (0 == ReadJoypad(0)));

while (ReadJoypad(0) != 0);

ClearBuffer();

SetRenderingParameters((21), (224));
}

void ClearObjectStore(void)
{
uint8_t i;
ObjectDescStruct *Current;

for(i = 0; i < MAX_OBJS; i++) {
	Current = (ObjectDescStruct*)&ObjectStore[i];
	Current->Type = 0xFF;
}
}

uint8_t GetFreeObject(void)
{
uint8_t i = 0;
uint8_t Particle = 0xFF;

ObjectDescStruct *Current;

do {
	Current = (ObjectDescStruct*)&ObjectStore[i];
	if (Current->Type == 0xFF) {
		return(i);
	}
	if (Current->Type == OBJ_PARTICLE) {
		Particle = i;
	}
	i++;
} while (i<MAX_OBJS);

return(Particle);
}

void DrawObjects(void) {
uint8_t i;
ObjectDescStruct *Current;

for(i = 0; i < MAX_OBJS; i++) {
	Current = (ObjectDescStruct*)&ObjectStore[i];
	if(Current->Type != 0xFF) {
		DrawPolarObjectFastC(Current->X_Hi,  Current->Y_Hi, Current->Type, Current->T_Hi, Current->Scale);
	}
}
}


void MoveObjects() {
uint8_t i;
ObjectDescStruct *Current;

for(i = 0; i < MAX_OBJS; i++) {
	Current = (ObjectDescStruct*)&ObjectStore[i];
	if(Current->Type != 0xFF) {
		Current->X16 = Current->X16 + ((Current->dX)<<4);
		Current->Y16 = Current->Y16 + ((Current->dY)<<4);
		Current->T16 = Current->T16 + ((Current->dT)<<3);

//		if((Current->Y_Hi > 223) && (Current->dY) > 0) Current->Y_Hi = 0;
//		if((Current->Y_Hi > 223) && (Current->dY) < 0) Current->Y_Hi = 223;

		if((Current->Y_Hi < 30) && (Current->dY) < 0) Current->Y_Hi = 223;  //lower bound of the screen
		if((Current->Y_Hi < 30) && (Current->dY) > 0) Current->Y_Hi = 30;//lower bound of the screen

		if((Current->Y_Hi > 223) && (Current->dY) > 0) Current->Y_Hi = 30;  //upper bound of the screen
		if((Current->Y_Hi > 223) && (Current->dY) < 0) Current->Y_Hi = 223;//upper bound of the screen

		//for some reason I was getting orphaned bullets, so I had to put in this code
		if (Current->Type == OBJ_BULLET) {
			if(Current->Owner != 1 && Current->Owner != 2){
				Current->Type = 0xFF;
			}

		}

		if(Current->Life != 0xFF) {
			Current->Life--;
			if(Current->Life == 0) {
				Current->Type = 0xFF;
//				if (Current->Type == OBJ_BULLET) {
//					Current->Type = 0xFF;
//				}else
//
//				if (Current->Type == OBJ_BROKEN_SHIP_1) {
//					//need to figure out which player just died
//					if(Current == player1.Ship){
//						//player1.Ship = NULL;
//						player1.Ship->Type = 0xFF;
//
//						player1.Lives--;
//						player1.State = playerDead;
//					}else if(Current == player2.Ship){
//						//player2.Ship = NULL;
//						player2.Ship->Type = 0xFF;
//						player2.Lives--;
//
//						player2.State = playerDead;
//					}
//
//					Current->Type = 0xFF;
//					//p->Ship = NULL;
//					//Current = NULL;
//					//Current->Type = 0xFF;
//					//p->Lives--;
//					//UpdateStatusLine(1, 'L', p->Lives);
//				}else
//
//				if (Current->Type == OBJ_SHIP) {
//					Current->Type = OBJ_BROKEN_SHIP_1;
//					Current->Life = 60;
//					NewObject(OBJ_BROKEN_SHIP_2, Current->X_Hi, Current->Y_Hi, Current->T_Hi, Current->dX + rand()%4-2, Current->dY + rand()%4-2, Current->dT + rand()%80-40, 255, 60);
//					NewObject(OBJ_BROKEN_SHIP_3, Current->X_Hi, Current->Y_Hi, Current->T_Hi, Current->dX + rand()%4-2, Current->dY + rand()%4-2, Current->dT + rand()%80-40, 255, 60);
//					NewObject(OBJ_BROKEN_SHIP_4, Current->X_Hi, Current->Y_Hi, Current->T_Hi, Current->dX + rand()%4-2, Current->dY + rand()%4-2, Current->dT + rand()%80-40, 255, 60);
//				}else {
//					Current->Type = 0xFF;
//				}

			}
		}
	}
}
}


uint8_t CheckCollision(ObjectDescStruct *Ob1, ObjectDescStruct *Ob2) {  //Ob1 is Ship/bullet  Ob2 is rock

//  Idea here to save both time and improve accuracy of small rock collision detection.
//
//	1, Make bounding box check dynamic (25 pixels is too large a comparison for small rock and anything
//			So make bound-check a variable that is dependant on rock size (1,2 or 3) and bullet-or-ship.
//
//  2, instead of doing "Dist*scale" for every point in a rock and every point in a bullet/ship
//       do Dist/(other)Scale for the points in the bullet/ship only and leave rock "unscaled"
//       This will save avg of 12 MULs per rock.  The DIV is expensive, but will do a lookup table of 1/MUL = DIV
//       The lookup table will be slow and take 3 clocks from flash but only has to be done once per deep-collision
//       detection.  Just need to check if it is accurate enough.




uint8_t i,j;

uint8_t AbsDistCheck;

uint8_t Dist1Read;
uint8_t Dist2Read;

PolarPointStruct PP1, PP2, PPX;
PointStruct      P1, P2, P3, PX;
PointStruct      Ob1Point;

AbsDistCheck = (Ob2->Scale >> 3) + 4;						// This is fairly dodgy "scale to bounding box" maths that "just works"
if (Ob1->Type == OBJ_SHIP) AbsDistCheck = AbsDistCheck + 4;			// in this case.  It needs some more thought to be general purpose.
if (Ob1->Type == OBJ_MIS_BLAST) AbsDistCheck = AbsDistCheck + 30;			// in this case.  It needs some more thought to be general purpose.

if((abs(Ob1->X_Hi - Ob2->X_Hi) < AbsDistCheck) &&
   (abs(Ob1->Y_Hi - Ob2->Y_Hi) < AbsDistCheck)) { // Possible collision (By bounding Box)

	Ob1Point.X = Ob1->X_Hi;
	Ob1Point.Y = Ob1->Y_Hi;

	P1.X = Ob2->X_Hi;
	P1.Y = Ob2->Y_Hi;

	i = 0;

	Dist1Read = pgm_read_byte(&PolarObjects[Ob2->Type].Points[i].Dist);
	PP2.Dist  = (Dist1Read * Ob2->Scale)>>8;
	PP2.Theta = pgm_read_byte(&PolarObjects[Ob2->Type].Points[i].Theta) + Ob2->T_Hi;

	while (Dist1Read != 0xFF) {

		PP1 = PP2;

		i++;
		Dist1Read = pgm_read_byte(&PolarObjects[Ob2->Type].Points[i].Dist);
		PP2.Dist  = (Dist1Read * Ob2->Scale)>>8;;
		PP2.Theta = pgm_read_byte(&PolarObjects[Ob2->Type].Points[i].Theta) + Ob2->T_Hi;

		P2 = PolarToPoint(P1, PP1);
		P3 = PolarToPoint(P1, PP2);

		if(Dist1Read == 0xFF) break;

		j = 0;

		Dist2Read = pgm_read_byte(&PolarObjects[Ob1->Type].Points[j].Dist);
		PPX.Dist  = (Dist2Read * Ob1->Scale)>>8;
		PPX.Theta = pgm_read_byte(&PolarObjects[Ob1->Type].Points[j].Theta) + Ob1->T_Hi;

		while (Dist2Read != 0xFF) {

			PX = PolarToPoint(Ob1Point, PPX);

			if(PointInTriangle(P1, P2, P3, PX) == 1) {
				return(1);
			}

			j++;
			Dist2Read = pgm_read_byte(&PolarObjects[Ob1->Type].Points[j].Dist);
			PPX.Dist  = (Dist2Read * Ob1->Scale)>>8;
			PPX.Theta = pgm_read_byte(&PolarObjects[Ob1->Type].Points[j].Theta) + Ob1->T_Hi;
		}
	}
}

return(0);

}

void CollisionDetection(void) {
//keeping this pretty simple hopefully
//only checking collision between player 1 and player 2 ships and missiles
//if players collide then each lose a life but neither score a point
//if player gets shot with missile then opposing player scores a point


	uint8_t i, j;
	ObjectDescStruct *Current;
	ObjectDescStruct *Compare;

	Current = player1.Ship;
	Compare = player2.Ship;
	//check players first
	if (CheckCollision(Current, Compare) != 0) {
		Current->Life = 1;
		Compare->Life = 1;
		player1.State = playerDead;
		player2.State = playerDead;
	}

	//next checking missiles
	for(i = 0; i < (MAX_OBJS - 1); i++) {
		Current = (ObjectDescStruct*)&ObjectStore[i];

		//if current is a missile...
		if (Current->Type == OBJ_BULLET){
			//will need to tell whether bullet is enemies
			//check collision
			if (CheckCollision(Current, player1.Ship) != 0 &&  Current->Owner != 1) {
				player1.Ship->Life = 1;
				player1.State = playerDead;
				player2.Score++;
			}
			if (CheckCollision(Current, player2.Ship) != 0 &&  Current->Owner != 2) {
				player2.Ship->Life = 1;
				player2.State = playerDead;
				player1.Score++;
			}

		}

	}

}



PointStruct PolarToPoint(PointStruct P1, PolarPointStruct PP1) {

PointStruct PX;

PX.X = P1.X + SinMulFastC(PP1.Theta, PP1.Dist);
PX.Y = P1.Y + CosMulFastC(PP1.Theta, PP1.Dist);

return(PX);
}

uint8_t PointInTriangle(PointStruct P1, PointStruct P2, PointStruct P3, PointStruct PX) {

int16_t PlaneAB;
int16_t PlaneBC;
int16_t PlaneCA;


// For testing collision detection
/*
SetPixelFastC(P1.X, P1.Y);
SetPixelFastC(P2.X, P2.Y);
SetPixelFastC(P3.X, P3.Y);
*/


PlaneAB = ((uint8_t)P1.X - (uint8_t)PX.X) * ((uint8_t)P2.Y - (uint8_t)PX.Y) - ((uint8_t)P2.X - (uint8_t)PX.X) * ((uint8_t)P1.Y - (uint8_t)PX.Y);
if(PlaneAB > 0) return(0);

PlaneBC = ((uint8_t)P2.X - (uint8_t)PX.X) * ((uint8_t)P3.Y - (uint8_t)PX.Y) - ((uint8_t)P3.X - (uint8_t)PX.X) * ((uint8_t)P2.Y - (uint8_t)PX.Y);
if(PlaneBC > 0) return(0);

PlaneCA = ((uint8_t)P3.X - (uint8_t)PX.X) * ((uint8_t)P1.Y - (uint8_t)PX.Y) - ((uint8_t)P1.X - (uint8_t)PX.X) * ((uint8_t)P3.Y - (uint8_t)PX.Y);
if(PlaneCA > 0) return(0);

return(1);
}


uint8_t NewParticle(uint8_t X, uint8_t Y, int8_t dX, int8_t dY){

ObjectDescStruct *NewObj;
uint8_t NewObjNum;

NewObjNum = GetFreeObject();

if(NewObjNum != 0xFF) {

	NewObj = ((ObjectDescStruct*)&ObjectStore[NewObjNum]);

	NewObj->Type  =  OBJ_PARTICLE;
	NewObj->X_Hi  =     X;
	NewObj->Y_Hi  =     Y;
	NewObj->T_Hi  =     0;
	NewObj->dX    =    dX;
	NewObj->dY    =    dY;
	NewObj->dT    =     0;
	NewObj->Scale =     1;
	NewObj->Life  =    15;

}
return(NewObjNum);
}

uint8_t NewBullet(uint8_t X, uint8_t Y, int8_t dX, int8_t dY, uint8_t L, uint8_t owner)
{
ObjectDescStruct *NewObj;
uint8_t NewObjNum;

NewObjNum = GetFreeObject();

if(NewObjNum != 0xFF) {

	NewObj = ((ObjectDescStruct*)&ObjectStore[NewObjNum]);

	NewObj->Type  =   OBJ_BULLET;
	NewObj->X_Hi  =   X;
	NewObj->Y_Hi  =   Y;
	NewObj->T_Hi  =   0;
	NewObj->dX    =  dX;
	NewObj->dY    =  dY;
	NewObj->dT    =   0;
	NewObj->Scale =   1;
	NewObj->Life  =   L;
	NewObj->Owner =	  owner;

}
return(NewObjNum);
}


uint8_t NewShip(player *p) {

ObjectDescStruct *NewObj;
uint8_t NewObjNum;
uint8_t shipType = OBJ_SHIP;

if(p->ShipType > 0){
	shipType = p->ShipType;
}

NewObjNum = GetFreeObject();

if(NewObjNum != 0xFF) {

	NewObj = ((ObjectDescStruct*)&ObjectStore[NewObjNum]);

	NewObj->Type  =   shipType;
	NewObj->X_Hi  = p->SpawnX;
	NewObj->Y_Hi  = p->SpawnY;
	NewObj->T_Hi  = p->T_Hi;
	NewObj->dX    =   0;
	NewObj->dY    =   0;
	NewObj->dT    =   0;
	NewObj->Scale = 255;
	NewObj->Life  =   0;

}
return(NewObjNum);
}

uint8_t NewObject(uint8_t Type, uint8_t X, uint8_t Y, uint8_t T, int8_t dX, int8_t dY, int8_t dT, uint8_t Scale, uint8_t Life) {

ObjectDescStruct *NewObj;
uint8_t NewObjNum;

NewObjNum = GetFreeObject();

if(NewObjNum != 0xFF) {

	NewObj = ((ObjectDescStruct*)&ObjectStore[NewObjNum]);

	NewObj->Type  =  Type;
	NewObj->X_Hi  =     X;
	NewObj->Y_Hi  =     Y;
	NewObj->T_Hi  =     T;
	NewObj->dX    =    dX;
	NewObj->dY    =    dY;
	NewObj->dT    =    dT;
	NewObj->Scale = Scale;
	NewObj->Life  =  Life;

}
return(NewObjNum);
}
