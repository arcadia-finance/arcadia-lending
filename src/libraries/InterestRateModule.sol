import "./DataTypes.sol";

library InterestRateModule {

    // TODO: Add safe math
    function calculateInterestRate(uint utilisation, DataTypes.InterestRateConfiguration memory config) {
        if (utilisation >= config.utilisationThreshold) {
            uint lowSlopeInterest = config.utilisationThreshold * config.lowSlope;
            uint highSlopeInterest = (utilisation - config.utilisationThreshold) * config.highSlope;
            return config.baseRate + lowSlopeInterest + highSlopeInterest;
        } else {
            return config.baseRate + config.lowSlope * utilisation;
        }
    }
}