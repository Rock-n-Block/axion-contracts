
const decimals_div = 1e18;
const seconds_in_day = 86400;

function calc_shares(amount, stakingDays, shareRate) {
    let sd = stakingDays > 1820 ? 1820 : stakingDays;
    return amount * (1819+sd)/(1820*shareRate);
}

function calc_shares_from_stake_event(amount, start, end, shareRate) {
    amount /= decimals_div;
    let stakingDays = (end-start) / seconds_in_day;
    return calc_shares(amount, stakingDays, shareRate);
}

module.exports = {
    calc_shares,
    calc_shares_from_stake_event
}

