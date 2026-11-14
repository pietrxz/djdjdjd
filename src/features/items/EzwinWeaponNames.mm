#include "unity/EzwinUnity.h"

const char *EzwinWeaponName(int weapon) {
    switch (weapon) {
        case 0: return "";
        case 4: return "AK47";
        case 5: return "M14";
        case 6: return "M4";
        case 7: return "SA58";
        case 8: return "MR96";
        case 9: return "HK417";
        case 10: return "SG551";
        case 11: return "URatio";
        case 12: return "Smoke";
        case 13: return "Flash";
        case 14: return "MTX";
        case 15: return "MP5";
        case 16: return "XD45";
        case 17: return "FP6";
        case 18: return "Super90";
        case 19: return "AUG";
        case 20: return "P90";
        case 21: return "P250";
        case 22: return "HE";
        case 103: return "Knife";
        case 105: return "GSR1911";
        case 106: return "MP7";
        case 3078: return "TRG";
        case 4009: return "Vector";
        case 6525: return "M1887";
        case 6712: return "MPX";
        case 7073: return "SVD";
        case 7519: return "Deagle";
        case 13707: return "AR15";
        case 14680: return "SCARH";
        case 15079: return "KSG";
        case 18576: return "Molotov";
        default: return "";
    }
}
