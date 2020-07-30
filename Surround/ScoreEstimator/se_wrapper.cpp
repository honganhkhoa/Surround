//
//  se_wrapper.cpp
//  Surround
//
//  Created by Anh Khoa Hong on 7/29/20.
//

#include <stdio.h>
#include <stdlib.h>

#include "Goban.h"

extern "C" void se_estimate(int width, int height, int *data, int player_to_move, int trials, float tolerance) {
    Goban goban(width, height);
    int i = 0;
    
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
//            printf("%d ", data[i]);
            goban.board[y][x] = data[i++];
        }
    }
    
    Grid estimated = goban.estimate((Color)player_to_move, trials, tolerance, false);

    i = 0;
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            data[i++] = estimated[y][x];
        }
    }
}
