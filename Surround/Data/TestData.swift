//
//  TestData.swift
//  Surround
//
//  Created by Anh Khoa Hong on 5/21/20.
//

import Foundation

class TestData {
    static var Scored19x19Korean: Game { sampleGame(id: 0) }
    static var Resigned19x19HandicappedWithInitialState: Game {
        let game = sampleGame(id: 1)
        game.ogsRawData = [
            "players": [
                "black": [
                    "icon": "https://secure.gravatar.com/avatar/7e8d12fdf00911f6b573b6644b518f4d?s=32&d=retro"
                ],
                "white": [
                    "icon": "https://b0c2ddc39d13e1c0ddad-93a52a5bc9e7cc06050c1a999beb3694.ssl.cf1.rackcdn.com/bb1794c4b0538ce0068287464079d02e-32.png"
                ]
            ]
        ]
        return game
    }
    static var Resigned9x9Japanese: Game { sampleGame(id: 2) }
    
    static func sampleGame(id: Int = 0) -> Game {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let ogsGame = try! decoder.decode(OGSGame.self, from: testData[id][0].data(using: .utf8)!)
        return Game(ogsGame: ogsGame)
    }
    
    static let testData : [[String]] = [
        // MARK: - W+ Scored, 19x19, Korean
        // MARK: - #18759438
        ["""
        {
            "white_player_id": 314459,
            "black_player_id": 356,
            "game_id": 18759438,
            "game_name": "Tournament Game: 1st 3 Kyu to 3 Dan Tournament (50283) R:1 (HongAnhKhoa vs Dyonn)",
            "private": false,
            "pause_on_weekends": true,
            "players": {
                "black": {
                    "username": "Dyonn",
                    "rank": 28.105412404704705,
                    "professional": false,
                    "egf": 1633.77,
                    "id": 356,
                    "accepted_stones": "qapbqbhdheiehfifjfjghhihjhkheigiiijiejgjijikjkkkjlqlbmjmjnlnqnfpcqbrdrer"
                },
                "white": {
                    "username": "HongAnhKhoa",
                    "rank": 28.513949148811413,
                    "professional": false,
                    "egf": 1720.594,
                    "id": 314459,
                    "accepted_stones": "qapbqbhdheiehfifjfjghhihjhkheigiiijiejgjijikjkkkjlqlbmjmjnlnqnfpcqbrdrer"
                }
            },
            "ranked": true,
            "disable_analysis": false,
            "handicap": 0,
            "komi": 6.5,
            "width": 19,
            "height": 19,
            "rules": "korean",
            "tournament_id": 50283,
            "tournament_round": 1,
            "time_control": {
                "system": "fischer",
                "time_control": "fischer",
                "speed": "correspondence",
                "pause_on_weekends": true,
                "time_increment": 86400,
                "initial_time": 259200,
                "max_time": 604800
            },
            "phase": "finished",
            "history": [],
            "initial_player": "black",
            "moves": [
                [
                    15,
                    3,
                    3854269
                ],
                [
                    15,
                    15,
                    67690194
                ],
                [
                    2,
                    3,
                    10271123
                ],
                [
                    3,
                    15,
                    34166712
                ],
                [
                    4,
                    2,
                    37247392
                ],
                [
                    3,
                    9,
                    83919093
                ],
                [
                    16,
                    9,
                    507423
                ],
                [
                    16,
                    2,
                    77624823
                ],
                [
                    16,
                    3,
                    2124217
                ],
                [
                    15,
                    2,
                    1682264
                ],
                [
                    14,
                    2,
                    1885902
                ],
                [
                    14,
                    1,
                    57159498
                ],
                [
                    13,
                    1,
                    28954647
                ],
                [
                    13,
                    2,
                    1728282
                ],
                [
                    14,
                    3,
                    88225
                ],
                [
                    12,
                    1,
                    1470747
                ],
                [
                    15,
                    1,
                    781206
                ],
                [
                    13,
                    0,
                    51615577
                ],
                [
                    16,
                    1,
                    25803584
                ],
                [
                    9,
                    2,
                    5109310
                ],
                [
                    9,
                    15,
                    11532608
                ],
                [
                    5,
                    16,
                    42655700
                ],
                [
                    13,
                    16,
                    27662643
                ],
                [
                    16,
                    13,
                    4063045
                ],
                [
                    16,
                    16,
                    7123701
                ],
                [
                    15,
                    16,
                    62151648
                ],
                [
                    15,
                    17,
                    8646848
                ],
                [
                    14,
                    17,
                    229165664
                ],
                [
                    16,
                    17,
                    34210672
                ],
                [
                    13,
                    17,
                    155071632
                ],
                [
                    12,
                    16,
                    13490502
                ],
                [
                    12,
                    17,
                    167488
                ],
                [
                    11,
                    16,
                    65607
                ],
                [
                    14,
                    16,
                    49989
                ],
                [
                    17,
                    14,
                    50503
                ],
                [
                    12,
                    14,
                    3561269
                ],
                [
                    11,
                    17,
                    1534181
                ],
                [
                    15,
                    8,
                    83023
                ],
                [
                    16,
                    8,
                    52823
                ],
                [
                    15,
                    6,
                    8609464
                ],
                [
                    16,
                    7,
                    278324
                ],
                [
                    15,
                    7,
                    163803
                ],
                [
                    16,
                    6,
                    43805
                ],
                [
                    8,
                    17,
                    160311610
                ],
                [
                    11,
                    13,
                    2142439
                ],
                [
                    11,
                    14,
                    15691916
                ],
                [
                    10,
                    14,
                    177816
                ],
                [
                    10,
                    13,
                    132615016
                ],
                [
                    9,
                    13,
                    24059874
                ],
                [
                    10,
                    12,
                    2632889
                ],
                [
                    9,
                    12,
                    1558832
                ],
                [
                    10,
                    11,
                    56017531
                ],
                [
                    9,
                    11,
                    26045116
                ],
                [
                    12,
                    12,
                    7257589
                ],
                [
                    10,
                    10,
                    75842
                ],
                [
                    10,
                    15,
                    56240063
                ],
                [
                    9,
                    16,
                    24196305
                ],
                [
                    9,
                    14,
                    1417623
                ],
                [
                    8,
                    14,
                    43556
                ],
                [
                    10,
                    14,
                    147911085
                ],
                [
                    7,
                    15,
                    22457533
                ],
                [
                    10,
                    16,
                    165073404
                ],
                [
                    9,
                    17,
                    8718200
                ],
                [
                    8,
                    13,
                    438596095
                ],
                [
                    7,
                    13,
                    2863215
                ],
                [
                    8,
                    12,
                    74889014
                ],
                [
                    9,
                    10,
                    3983288
                ],
                [
                    7,
                    11,
                    49579921
                ],
                [
                    7,
                    12,
                    30016524
                ],
                [
                    8,
                    11,
                    833814805
                ],
                [
                    6,
                    11,
                    33711425
                ],
                [
                    7,
                    10,
                    159969766
                ],
                [
                    5,
                    12,
                    14302040
                ],
                [
                    7,
                    8,
                    1157106
                ],
                [
                    15,
                    9,
                    58458
                ],
                [
                    14,
                    9,
                    299474528
                ],
                [
                    14,
                    10,
                    41431633
                ],
                [
                    13,
                    10,
                    387815136
                ],
                [
                    14,
                    8,
                    194404
                ],
                [
                    13,
                    9,
                    56543551
                ],
                [
                    15,
                    5,
                    5967797
                ],
                [
                    13,
                    7,
                    49065350
                ],
                [
                    12,
                    8,
                    20989100
                ],
                [
                    13,
                    8,
                    53947837
                ],
                [
                    9,
                    7,
                    33450460
                ],
                [
                    7,
                    6,
                    768403371
                ],
                [
                    11,
                    5,
                    5868690
                ],
                [
                    10,
                    6,
                    247786562
                ],
                [
                    9,
                    6,
                    30743178
                ],
                [
                    10,
                    5,
                    392332283
                ],
                [
                    9,
                    5,
                    20949488
                ],
                [
                    10,
                    4,
                    12554525
                ],
                [
                    7,
                    5,
                    342007
                ],
                [
                    6,
                    5,
                    84205169
                ],
                [
                    7,
                    4,
                    1152871
                ],
                [
                    6,
                    4,
                    367118
                ],
                [
                    7,
                    3,
                    464004
                ],
                [
                    6,
                    3,
                    54302976
                ],
                [
                    6,
                    2,
                    21660906
                ],
                [
                    6,
                    6,
                    133684701
                ],
                [
                    6,
                    9,
                    38121893
                ],
                [
                    7,
                    9,
                    54598105
                ],
                [
                    10,
                    7,
                    32971836
                ],
                [
                    6,
                    14,
                    63085416
                ],
                [
                    7,
                    14,
                    23212837
                ],
                [
                    2,
                    6,
                    163923176
                ],
                [
                    2,
                    11,
                    5451251
                ],
                [
                    2,
                    14,
                    89068191
                ],
                [
                    1,
                    9,
                    84665009
                ],
                [
                    3,
                    11,
                    258984933
                ],
                [
                    3,
                    12,
                    13232788
                ],
                [
                    2,
                    12,
                    211247718
                ],
                [
                    4,
                    11,
                    35462079
                ],
                [
                    3,
                    10,
                    2415961
                ],
                [
                    1,
                    12,
                    31675
                ],
                [
                    2,
                    13,
                    59880565
                ],
                [
                    1,
                    7,
                    28834935
                ],
                [
                    2,
                    10,
                    751240568
                ],
                [
                    1,
                    6,
                    18655522
                ],
                [
                    1,
                    10,
                    420898512
                ],
                [
                    6,
                    8,
                    16407737
                ],
                [
                    4,
                    7,
                    54013964
                ],
                [
                    4,
                    8,
                    31080775
                ],
                [
                    3,
                    8,
                    64259098
                ],
                [
                    7,
                    7,
                    23259919
                ],
                [
                    6,
                    7,
                    65135123
                ],
                [
                    8,
                    7,
                    19424512
                ],
                [
                    6,
                    10,
                    5389114
                ],
                [
                    4,
                    9,
                    103816
                ],
                [
                    4,
                    10,
                    4493047
                ],
                [
                    5,
                    15,
                    8874440
                ],
                [
                    6,
                    16,
                    764861479
                ],
                [
                    7,
                    17,
                    1154896
                ],
                [
                    7,
                    16,
                    43819971
                ],
                [
                    8,
                    16,
                    39350406
                ],
                [
                    6,
                    17,
                    148499025
                ],
                [
                    8,
                    18,
                    28818144
                ],
                [
                    6,
                    15,
                    142683932
                ],
                [
                    10,
                    17,
                    28531976
                ],
                [
                    9,
                    4,
                    84767232
                ],
                [
                    8,
                    4,
                    1353949
                ],
                [
                    2,
                    5,
                    83656410
                ],
                [
                    1,
                    4,
                    848126
                ],
                [
                    11,
                    7,
                    223149674
                ],
                [
                    14,
                    11,
                    39629567
                ],
                [
                    16,
                    11,
                    81834186
                ],
                [
                    15,
                    10,
                    4202459
                ],
                [
                    16,
                    15,
                    127350396
                ],
                [
                    17,
                    15,
                    39153837
                ],
                [
                    11,
                    8,
                    162113155
                ],
                [
                    14,
                    13,
                    11756210
                ],
                [
                    14,
                    14,
                    171507798
                ],
                [
                    13,
                    13,
                    3475204
                ],
                [
                    13,
                    14,
                    132480232
                ],
                [
                    16,
                    14,
                    82554
                ],
                [
                    10,
                    8,
                    634271
                ],
                [
                    9,
                    8,
                    263606
                ],
                [
                    9,
                    9,
                    81259481
                ],
                [
                    8,
                    9,
                    45047526
                ],
                [
                    10,
                    9,
                    84064319
                ],
                [
                    8,
                    8,
                    679427
                ],
                [
                    11,
                    10,
                    435253525
                ],
                [
                    8,
                    10,
                    2041202
                ],
                [
                    5,
                    10,
                    256409755
                ],
                [
                    8,
                    5,
                    7
                ],
                [
                    7,
                    2,
                    136778466
                ],
                [
                    8,
                    2,
                    7
                ],
                [
                    7,
                    1,
                    75257542
                ],
                [
                    8,
                    1,
                    6
                ],
                [
                    6,
                    1,
                    49551133
                ],
                [
                    11,
                    6,
                    524317
                ],
                [
                    9,
                    3,
                    70778577
                ],
                [
                    12,
                    7,
                    13980515
                ],
                [
                    11,
                    9,
                    45456654
                ],
                [
                    13,
                    6,
                    38453188
                ],
                [
                    12,
                    13,
                    78670374
                ],
                [
                    13,
                    11,
                    8142367
                ],
                [
                    12,
                    11,
                    59680395
                ],
                [
                    2,
                    16,
                    24370225
                ],
                [
                    3,
                    16,
                    730493297
                ],
                [
                    3,
                    17,
                    46134397
                ],
                [
                    1,
                    16,
                    174237640
                ],
                [
                    1,
                    17,
                    1659943
                ],
                [
                    1,
                    15,
                    5350172
                ],
                [
                    4,
                    17,
                    270515
                ],
                [
                    6,
                    18,
                    34655507
                ],
                [
                    7,
                    18,
                    41997270
                ],
                [
                    5,
                    13,
                    767095478
                ],
                [
                    4,
                    13,
                    12215596
                ],
                [
                    4,
                    14,
                    43887426
                ],
                [
                    4,
                    5,
                    40955710
                ],
                [
                    3,
                    4,
                    233960375
                ],
                [
                    5,
                    2,
                    30131762
                ],
                [
                    4,
                    4,
                    51132617
                ],
                [
                    5,
                    1,
                    32462259
                ],
                [
                    8,
                    3,
                    8349130
                ],
                [
                    11,
                    4,
                    591063
                ],
                [
                    9,
                    1,
                    305869137
                ],
                [
                    2,
                    7,
                    31481187
                ],
                [
                    3,
                    7,
                    49316341
                ],
                [
                    11,
                    2,
                    34948688
                ],
                [
                    11,
                    1,
                    75812451
                ],
                [
                    13,
                    3,
                    13247482
                ],
                [
                    12,
                    2,
                    597046337
                ],
                [
                    6,
                    12,
                    6961070
                ],
                [
                    14,
                    6,
                    169859087
                ],
                [
                    14,
                    5,
                    8960705
                ],
                [
                    14,
                    7,
                    151756198
                ],
                [
                    0,
                    10,
                    17029904
                ],
                [
                    0,
                    11,
                    42555052
                ],
                [
                    0,
                    9,
                    42090603
                ],
                [
                    1,
                    11,
                    77483946
                ],
                [
                    15,
                    14,
                    7489070
                ],
                [
                    12,
                    9,
                    56552228
                ],
                [
                    12,
                    6,
                    34352454
                ],
                [
                    11,
                    3,
                    306653038
                ],
                [
                    6,
                    13,
                    31784841
                ],
                [
                    5,
                    14,
                    153955165
                ],
                [
                    6,
                    0,
                    20380268
                ],
                [
                    8,
                    0,
                    61624417
                ],
                [
                    12,
                    3,
                    23667992
                ],
                [
                    10,
                    2,
                    12172234
                ],
                [
                    5,
                    3,
                    152391
                ],
                [
                    13,
                    12,
                    61679979
                ],
                [
                    14,
                    12,
                    16073041
                ],
                [
                    1,
                    5,
                    241454238
                ],
                [
                    0,
                    5,
                    20367648
                ],
                [
                    15,
                    0,
                    226369863
                ],
                [
                    16,
                    0,
                    27366018
                ],
                [
                    14,
                    0,
                    68330435
                ],
                [
                    5,
                    4,
                    22467822
                ],
                [
                    5,
                    5,
                    334930910
                ],
                [
                    2,
                    4,
                    9725736
                ],
                [
                    17,
                    2,
                    43416007
                ],
                [
                    3,
                    3,
                    1469797
                ],
                [
                    4,
                    6,
                    15022110
                ],
                [
                    17,
                    3,
                    23970762
                ],
                [
                    17,
                    1,
                    43405701
                ],
                [
                    18,
                    2,
                    53686138
                ],
                [
                    18,
                    1,
                    42137917
                ],
                [
                    18,
                    3,
                    33754262
                ],
                [
                    3,
                    13,
                    223123456
                ],
                [
                    4,
                    12,
                    38369118
                ],
                [
                    2,
                    8,
                    221665399
                ],
                [
                    1,
                    8,
                    37488567
                ],
                [
                    11,
                    18,
                    55115375
                ],
                [
                    10,
                    18,
                    30348975
                ],
                [
                    12,
                    18,
                    309267066
                ],
                [
                    14,
                    18,
                    33078296
                ],
                [
                    14,
                    15,
                    159286093
                ],
                [
                    5,
                    0,
                    17403265
                ],
                [
                    13,
                    18,
                    238246133
                ],
                [
                    15,
                    18,
                    18631745
                ],
                [
                    3,
                    5,
                    142513504
                ],
                [
                    4,
                    3,
                    27817105
                ],
                [
                    -1,
                    -1,
                    9880875
                ],
                [
                    -1,
                    -1,
                    4291261
                ]
            ],
            "allow_self_capture": false,
            "automatic_stone_removal": false,
            "free_handicap_placement": false,
            "aga_handicap_scoring": false,
            "allow_ko": false,
            "allow_superko": true,
            "superko_algorithm": "ssk",
            "score_territory": true,
            "score_territory_in_seki": false,
            "score_stones": false,
            "score_handicap": false,
            "score_prisoners": true,
            "score_passes": true,
            "white_must_pass_last": false,
            "opponent_plays_first_after_resume": true,
            "strict_seki_mode": false,
            "initial_state": {
                "black": "",
                "white": ""
            },
            "start_time": 1563570060,
            "original_disable_analysis": false,
            "clock": {
                "game_id": 18759438,
                "current_player": 314459,
                "black_player_id": 356,
                "white_player_id": 314459,
                "title": "Tournament Game: 1st 3 Kyu to 3 Dan Tournament (50283) R:1 (HongAnhKhoa vs Dyonn)",
                "last_move": 1583857202249,
                "expiration": 1584462002249,
                "black_time": {
                    "thinking_time": 604800,
                    "skip_bonus": false
                },
                "white_time": {
                    "thinking_time": 604800,
                    "skip_bonus": false
                },
                "now": 1583879747295,
                "paused_since": 1583857202249,
                "pause_delta": 0,
                "expiration_delta": 604800000,
                "stone_removal_mode": true,
                "stone_removal_expiration": 1583966147295
            },
            "pause_control": {
                "stone-removal": true
            },
            "paused_since": 1583857202249,
            "removed": "qapbqbhdheiehfifjfjghhihjhkheigiiijiejgjijikjkkkjlqlbmjmjnlnqnfpcqbrdrer",
            "auto_scoring_done": true,
            "score": {
                "white": {
                    "total": 126.5,
                    "stones": 0,
                    "territory": 78,
                    "prisoners": 42,
                    "scoring_positions": "jakalamakbqarasapbqbibicnblchdheiehfifjfigjghhihjhkhiijiijikjkkkjljmjnkdefdgfgfheifigiejfjgjoimkcllllmlnambmanbnaoboapcpepfpaqcqeqarbrcrdrerfrasbscsdsesfsdo",
                    "handicap": 0,
                    "komi": 6.5
                },
                "black": {
                    "total": 70,
                    "stones": 0,
                    "territory": 67,
                    "prisoners": 3,
                    "scoring_positions": "aabacadaeaabbbcbdbebacbcccdcadbdaemeneoepeqeresemfnfqfrfsfrgsgrhshrisirjsjqkrkskplqlrlslpmqmrmsmpnqnrnsnsosprqsqrrsrqsrsssagahaiipirjs",
                    "handicap": 0,
                    "komi": 0
                }
            },
            "winner": 314459,
            "outcome": "56.5 points",
            "end_time": 1583938533
        }
        """],
        // MARK: - W+ Resigned, 19x19, Handicapped with Initial State
        // MARK: - #23871959
        ["""
        {
            "white_player_id": 749506,
            "black_player_id": 757083,
            "game_id": 23871959,
            "game_name": "Friendly Match",
            "private": false,
            "pause_on_weekends": false,
            "players": {
                "black": {
                    "username": "bsktrgt",
                    "rank": 29.366184380692395,
                    "professional": false,
                    "egf": 999.523,
                    "id": 757083
                },
                "white": {
                    "username": "hhs214",
                    "rank": 31.560869142522165,
                    "professional": false,
                    "egf": 1153.853,
                    "id": 749506
                }
            },
            "ranked": true,
            "disable_analysis": false,
            "handicap": 2,
            "komi": 0.5,
            "width": 19,
            "height": 19,
            "rules": "japanese",
            "time_control": {
                "system": "byoyomi",
                "speed": "live",
                "main_time": 60,
                "period_time": 10,
                "periods": 5,
                "pause_on_weekends": false,
                "time_control": "byoyomi"
            },
            "phase": "finished",
            "initial_player": "white",
            "moves": [
                [
                    3,
                    3,
                    3145
                ],
                [
                    2,
                    3,
                    280
                ],
                [
                    2,
                    4,
                    2787
                ],
                [
                    2,
                    2,
                    1240
                ],
                [
                    3,
                    2,
                    2106
                ],
                [
                    1,
                    4,
                    780
                ],
                [
                    2,
                    5,
                    2446
                ],
                [
                    1,
                    5,
                    632
                ],
                [
                    2,
                    6,
                    1462
                ],
                [
                    3,
                    1,
                    602
                ],
                [
                    4,
                    1,
                    1360
                ],
                [
                    2,
                    1,
                    634
                ],
                [
                    5,
                    2,
                    757
                ],
                [
                    16,
                    16,
                    1599
                ],
                [
                    2,
                    16,
                    4001
                ],
                [
                    3,
                    16,
                    1674
                ],
                [
                    2,
                    15,
                    1898
                ],
                [
                    2,
                    13,
                    1033
                ],
                [
                    1,
                    13,
                    1787
                ],
                [
                    2,
                    12,
                    2090
                ],
                [
                    2,
                    14,
                    1873
                ],
                [
                    3,
                    14,
                    951
                ],
                [
                    1,
                    12,
                    1254
                ],
                [
                    2,
                    11,
                    710
                ],
                [
                    1,
                    11,
                    2122
                ],
                [
                    2,
                    10,
                    802
                ],
                [
                    13,
                    16,
                    3355
                ],
                [
                    10,
                    16,
                    1724
                ],
                [
                    15,
                    15,
                    2879
                ],
                [
                    16,
                    15,
                    1330
                ],
                [
                    15,
                    14,
                    1525
                ],
                [
                    14,
                    17,
                    630
                ],
                [
                    16,
                    14,
                    1743
                ],
                [
                    14,
                    16,
                    814
                ],
                [
                    13,
                    14,
                    1779
                ],
                [
                    14,
                    15,
                    1148
                ],
                [
                    12,
                    13,
                    2039
                ],
                [
                    10,
                    14,
                    2283
                ],
                [
                    16,
                    5,
                    2718
                ],
                [
                    16,
                    8,
                    2190
                ],
                [
                    14,
                    5,
                    8828
                ],
                [
                    13,
                    2,
                    1430
                ],
                [
                    16,
                    10,
                    1975
                ],
                [
                    14,
                    8,
                    1431
                ],
                [
                    17,
                    3,
                    2307
                ],
                [
                    16,
                    2,
                    1712
                ],
                [
                    12,
                    3,
                    2661
                ],
                [
                    12,
                    2,
                    2652
                ],
                [
                    12,
                    8,
                    5617
                ],
                [
                    13,
                    7,
                    1783
                ],
                [
                    11,
                    6,
                    2345
                ],
                [
                    13,
                    5,
                    1260
                ],
                [
                    14,
                    4,
                    3424
                ],
                [
                    13,
                    4,
                    1212
                ],
                [
                    14,
                    3,
                    2750
                ],
                [
                    13,
                    3,
                    916
                ],
                [
                    14,
                    2,
                    1467
                ],
                [
                    8,
                    2,
                    950
                ],
                [
                    14,
                    1,
                    6105
                ],
                [
                    11,
                    12,
                    7757
                ],
                [
                    9,
                    12,
                    4642
                ],
                [
                    8,
                    13,
                    2056
                ],
                [
                    4,
                    13,
                    4170
                ],
                [
                    6,
                    12,
                    3098
                ],
                [
                    4,
                    11,
                    5368
                ],
                [
                    5,
                    14,
                    1777
                ],
                [
                    5,
                    10,
                    6166
                ],
                [
                    4,
                    9,
                    11578
                ],
                [
                    5,
                    9,
                    4100
                ],
                [
                    2,
                    8,
                    1178
                ],
                [
                    1,
                    6,
                    3201
                ],
                [
                    4,
                    7,
                    988
                ],
                [
                    5,
                    8,
                    4916
                ],
                [
                    3,
                    7,
                    3871
                ],
                [
                    6,
                    6,
                    4246
                ],
                [
                    4,
                    5,
                    1568
                ],
                [
                    4,
                    4,
                    1952
                ],
                [
                    5,
                    5,
                    1598
                ],
                [
                    0,
                    5,
                    3307
                ],
                [
                    0,
                    3,
                    1430
                ],
                [
                    7,
                    3,
                    8413
                ],
                [
                    7,
                    2,
                    1994
                ],
                [
                    6,
                    3,
                    3430
                ],
                [
                    8,
                    3,
                    2721
                ],
                [
                    8,
                    4,
                    4003
                ],
                [
                    9,
                    4,
                    1443
                ],
                [
                    3,
                    13,
                    2605
                ],
                [
                    7,
                    4,
                    5396
                ],
                [
                    6,
                    4,
                    3148
                ],
                [
                    8,
                    5,
                    779
                ],
                [
                    6,
                    5,
                    1814
                ],
                [
                    4,
                    10,
                    4965
                ],
                [
                    5,
                    11,
                    4620
                ],
                [
                    3,
                    11,
                    1137
                ],
                [
                    4,
                    8,
                    5446
                ],
                [
                    3,
                    8,
                    1406
                ],
                [
                    3,
                    9,
                    1671
                ],
                [
                    3,
                    10,
                    1377
                ],
                [
                    5,
                    13,
                    3012
                ],
                [
                    6,
                    13,
                    1791
                ],
                [
                    3,
                    17,
                    2951
                ],
                [
                    4,
                    17,
                    2044
                ],
                [
                    2,
                    17,
                    1813
                ],
                [
                    5,
                    6,
                    3347
                ],
                [
                    5,
                    7,
                    4614
                ],
                [
                    3,
                    5,
                    1072
                ],
                [
                    3,
                    6,
                    1574
                ],
                [
                    4,
                    6,
                    3582
                ],
                [
                    3,
                    4,
                    1438
                ],
                [
                    1,
                    7,
                    796
                ],
                [
                    1,
                    9,
                    1832
                ],
                [
                    1,
                    10,
                    1318
                ],
                [
                    0,
                    10,
                    1642
                ],
                [
                    0,
                    11,
                    1256
                ],
                [
                    0,
                    12,
                    2082
                ],
                [
                    1,
                    8,
                    1614
                ],
                [
                    0,
                    9,
                    1648
                ],
                [
                    0,
                    8,
                    1781
                ],
                [
                    1,
                    15,
                    4381
                ],
                [
                    2,
                    9,
                    1695
                ],
                [
                    0,
                    11,
                    2182
                ],
                [
                    0,
                    6,
                    692
                ],
                [
                    0,
                    7,
                    1717
                ],
                [
                    5,
                    12,
                    3894
                ],
                [
                    4,
                    12,
                    3285
                ],
                [
                    0,
                    6,
                    747
                ],
                [
                    5,
                    17,
                    6017
                ],
                [
                    4,
                    16,
                    3312
                ],
                [
                    0,
                    7,
                    2546
                ],
                [
                    0,
                    14,
                    4819
                ],
                [
                    1,
                    14,
                    4198
                ],
                [
                    0,
                    6,
                    1904
                ],
                [
                    5,
                    16,
                    6352
                ],
                [
                    5,
                    15,
                    5514
                ],
                [
                    0,
                    7,
                    2812
                ],
                [
                    5,
                    4,
                    2285
                ],
                [
                    0,
                    6,
                    4596
                ]
            ],
            "allow_self_capture": false,
            "automatic_stone_removal": false,
            "free_handicap_placement": false,
            "aga_handicap_scoring": false,
            "allow_ko": false,
            "allow_superko": true,
            "superko_algorithm": "ssk",
            "score_territory": true,
            "score_territory_in_seki": false,
            "score_stones": false,
            "score_handicap": false,
            "score_prisoners": true,
            "score_passes": true,
            "white_must_pass_last": false,
            "opponent_plays_first_after_resume": true,
            "strict_seki_mode": false,
            "initial_state": {
                "black": "pddp",
                "white": ""
            },
            "start_time": 1589279239,
            "original_disable_analysis": false,
            "clock": {
                "game_id": 23871959,
                "current_player": 757083,
                "black_player_id": 757083,
                "white_player_id": 749506,
                "title": "Friendly Match",
                "last_move": 1589279595497,
                "expiration": 1589279645497,
                "black_time": {
                    "thinking_time": 0,
                    "periods": 5,
                    "period_time": 10
                },
                "white_time": {
                    "thinking_time": 0,
                    "periods": 5,
                    "period_time": 10
                }
            },
            "winner": 749506,
            "outcome": "Resignation",
            "end_time": 1589279598
        }
        """],
        // MARK: - B+ Resigned, 9x9
        // MARK: - #25076729
        ["""
        {
          "white_player_id": 298971,
          "black_player_id": 778820,
          "game_id": 25076729,
          "game_name": "Friendly Match",
          "private": false,
          "pause_on_weekends": false,
          "players": {
            "black": {
              "username": "Phidzad",
              "rank": 21.918201704885952,
              "professional": false,
              "id": 778820
            },
            "white": {
              "username": "Youngparist",
              "rank": 22.07271721620448,
              "professional": false,
              "id": 298971
            }
          },
          "ranked": true,
          "disable_analysis": false,
          "handicap": 0,
          "komi": 5.5,
          "width": 9,
          "height": 9,
          "rules": "japanese",
          "time_control": {
            "system": "simple",
            "speed": "live",
            "per_move": 10,
            "pause_on_weekends": false,
            "time_control": "simple"
          },
          "phase": "finished",
          "initial_player": "black",
          "moves": [
            [
              6,
              5,
              2393
            ],
            [
              3,
              5,
              1174
            ],
            [
              2,
              3,
              1388
            ],
            [
              6,
              2,
              1379
            ],
            [
              4,
              2,
              1142
            ],
            [
              5,
              4,
              1266
            ],
            [
              5,
              6,
              2771
            ],
            [
              4,
              6,
              939
            ],
            [
              7,
              3,
              1583
            ],
            [
              7,
              2,
              1260
            ],
            [
              5,
              7,
              1138
            ],
            [
              6,
              3,
              1188
            ],
            [
              7,
              4,
              1275
            ],
            [
              4,
              7,
              1275
            ],
            [
              1,
              5,
              1682
            ],
            [
              7,
              6,
              3096
            ],
            [
              7,
              7,
              2542
            ],
            [
              6,
              6,
              2081
            ],
            [
              5,
              5,
              1639
            ],
            [
              6,
              7,
              4617
            ],
            [
              6,
              8,
              1466
            ],
            [
              8,
              7,
              1830
            ],
            [
              7,
              8,
              3612
            ],
            [
              7,
              5,
              1895
            ],
            [
              6,
              4,
              1502
            ],
            [
              8,
              6,
              3117
            ],
            [
              8,
              4,
              2103
            ],
            [
              3,
              2,
              4402
            ],
            [
              3,
              3,
              1826
            ],
            [
              4,
              3,
              1006
            ],
            [
              4,
              4,
              1847
            ],
            [
              5,
              3,
              1389
            ],
            [
              4,
              5,
              3092
            ],
            [
              3,
              4,
              1031
            ],
            [
              2,
              2,
              4069
            ],
            [
              3,
              1,
              3712
            ],
            [
              8,
              5,
              3548
            ],
            [
              2,
              1,
              5718
            ],
            [
              1,
              4,
              5360
            ],
            [
              2,
              6,
              2842
            ],
            [
              1,
              6,
              1993
            ],
            [
              1,
              7,
              861
            ],
            [
              0,
              7,
              1763
            ],
            [
              1,
              8,
              4192
            ],
            [
              3,
              7,
              1871
            ],
            [
              3,
              8,
              1338
            ],
            [
              2,
              7,
              4660
            ],
            [
              3,
              6,
              1556
            ],
            [
              1,
              1,
              2885
            ],
            [
              2,
              8,
              1546
            ],
            [
              1,
              0,
              2233
            ],
            [
              2,
              0,
              4917
            ],
            [
              0,
              2,
              2465
            ]
          ],
          "allow_self_capture": false,
          "automatic_stone_removal": false,
          "free_handicap_placement": false,
          "aga_handicap_scoring": false,
          "allow_ko": false,
          "allow_superko": true,
          "superko_algorithm": "ssk",
          "score_territory": true,
          "score_territory_in_seki": false,
          "score_stones": false,
          "score_handicap": false,
          "score_prisoners": true,
          "score_passes": true,
          "white_must_pass_last": false,
          "opponent_plays_first_after_resume": true,
          "strict_seki_mode": false,
          "initial_state": {
            "black": "",
            "white": ""
          },
          "start_time": 1593517436,
          "original_disable_analysis": false,
          "clock": {
            "game_id": 25076729,
            "current_player": 298971,
            "black_player_id": 778820,
            "white_player_id": 298971,
            "title": "Friendly Match",
            "last_move": 1593517559475,
            "expiration": 1593517569475,
            "black_time": 10,
            "white_time": 1593517569475
          },
          "winner": 778820,
          "outcome": "Resignation",
          "end_time": 1593517560
        }
        """]
    ]

}
