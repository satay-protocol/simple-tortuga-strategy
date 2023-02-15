module simple_tortuga_strategy::simple_tortuga_strategy {

    use std::signer;

    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::aptos_coin::AptosCoin;

    use satay_coins::strategy_coin::StrategyCoin;

    use satay::satay;
    use satay::strategy_config;
    use liquidswap::router_v2;
    use tortuga::staked_aptos_coin::StakedAptosCoin;
    use liquidswap::curves::Stable;

    friend simple_tortuga_strategy::simple_tortuga_vault_strategy;

    struct SimpleTortugaStrategy has drop {}

    // governance functions

    /// initialize StrategyCapability<AptosCoin, SimpleTortugaStrategy> and StrategyCoin<AptosCoin, SimpleTortugaStrategy>
    /// * governance: &signer - must have the governance role on satay::global_config
    public entry fun initialize(governance: &signer) {
        satay::new_strategy<AptosCoin, SimpleTortugaStrategy>(governance, SimpleTortugaStrategy {});
        satay::strategy_add_coin<AptosCoin, SimpleTortugaStrategy, StakedAptosCoin>(SimpleTortugaStrategy {});
    }

    // strategy manager functions

    /// claim rewards, convert to AptosCoin, and deposit back into the strategy
    /// * strategy_manager: &signer - must have the strategy manager role account on satay::strategy_config
    public entry fun tend(strategy_manager: &signer) {
        strategy_config::assert_strategy_manager<AptosCoin, SimpleTortugaStrategy>(
            strategy_manager,
            get_strategy_account_address(),
        );
    }

    // user functions

    /// deposit AptosCoin into the strategy for user, mint StrategyCoin<AptosCoin, SimpleTortugaStrategy> in return
    /// * user: &signer - must hold amount of AptosCoin
    /// * amount: u64 - the amount of AptosCoin to deposit
    public entry fun deposit(user: &signer, amount: u64) {
        let base_coins = coin::withdraw(user, amount);
        let strategy_coins = apply(base_coins);
        if(!coin::is_account_registered<StrategyCoin<AptosCoin, SimpleTortugaStrategy>>(signer::address_of(user))) {
            coin::register<StrategyCoin<AptosCoin, SimpleTortugaStrategy>>(user);
        };
        coin::deposit(signer::address_of(user), strategy_coins);
    }

    /// burn StrategyCoin<AptosCoin, SimpleTortugaStrategy> for user, withdraw AptosCoin from the strategy in return
    /// * user: &signer - must hold amount of StrategyCoin<AptosCoin, SimpleTortugaStrategy>
    /// * amount: u64 - the amount of StrategyCoin<AptosCoin, SimpleTortugaStrategy> to burn
    public entry fun withdraw(user: &signer, amount: u64) {
        let strategy_coins = coin::withdraw<StrategyCoin<AptosCoin, SimpleTortugaStrategy>>(user, amount);
        let aptos_coins = liquidate(strategy_coins);
        coin::deposit(signer::address_of(user), aptos_coins);
    }

    /// convert AptosCoin into StrategyCoin<AptosCoin, SimpleTortugaStrategy>
    /// * base_coins: Coin - the AptosCoin to convert
    public fun apply(base_coins: Coin<AptosCoin>): Coin<StrategyCoin<AptosCoin, SimpleTortugaStrategy>> {
        if(coin::value(&base_coins) == 0) {
            coin::destroy_zero(base_coins);
            return coin::zero<StrategyCoin<AptosCoin, SimpleTortugaStrategy>>()
        };
        let tapt = router_v2::swap_exact_coin_for_coin<AptosCoin, StakedAptosCoin, Stable>(
            base_coins,
            0
        );
        let tapt_amount = coin::value(&tapt);
        satay::strategy_deposit<AptosCoin, SimpleTortugaStrategy, StakedAptosCoin>(tapt, SimpleTortugaStrategy {});
        satay::strategy_mint<AptosCoin, SimpleTortugaStrategy>(tapt_amount, SimpleTortugaStrategy {})
    }

    /// convert StrategyCoin<AptosCoin, SimpleTortugaStrategy> into AptosCoin
    /// * strategy_coins: Coin<StrategyCoin<AptosCoin, SimpleTortugaStrategy>> - the StrategyCoin to convert
    public fun liquidate(strategy_coins: Coin<StrategyCoin<AptosCoin, SimpleTortugaStrategy>>): Coin<AptosCoin> {
        if(coin::value(&strategy_coins) == 0) {
            coin::destroy_zero(strategy_coins);
            return coin::zero<AptosCoin>()
        };
        let strategy_coin_value = coin::value(&strategy_coins);
        satay::strategy_burn(strategy_coins, SimpleTortugaStrategy {});
        let tapt = satay::strategy_withdraw<AptosCoin, SimpleTortugaStrategy, StakedAptosCoin>(
            strategy_coin_value,
            SimpleTortugaStrategy {}
        );
        router_v2::swap_exact_coin_for_coin<StakedAptosCoin, AptosCoin, Stable>(
            tapt,
            0
        )
    }

    // calculations

    /// calculate the amount of product coins that can be minted for a given amount of base coins
    /// * product_coin_amount: u64 - the amount of ProductCoin to be converted
    public fun calc_base_coin_amount(strategy_coin_amount: u64): u64 {
        router_v2::get_amount_out<StakedAptosCoin, AptosCoin, Stable>(strategy_coin_amount)
    }

    /// calculate the amount of base coins that can be liquidated for a given amount of product coins
    /// * base_coin_amount: u64 - the amount of AptosCoin to be converted
    public fun calc_product_coin_amount(base_coin_amount: u64): u64 {
        router_v2::get_amount_out<AptosCoin, StakedAptosCoin, Stable>(base_coin_amount)
    }

    // getters

    /// gets the address of the product account for AptosCoin
    public fun get_strategy_account_address(): address
    {
        satay::get_strategy_address<AptosCoin, SimpleTortugaStrategy>()
    }

    /// gets the witness for the SimpleTortugaStrategy
    public(friend) fun get_strategy_witness(): SimpleTortugaStrategy {
        SimpleTortugaStrategy {}
    }
}
