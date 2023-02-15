module simple_tortuga_strategy::simple_tortuga_vault_strategy {

    use aptos_framework::coin;

    use simple_tortuga_strategy::simple_tortuga_strategy::{Self, SimpleTortugaStrategy};

    use satay_coins::vault_coin::VaultCoin;

    use satay::base_strategy;
    use satay::satay;
    use satay_coins::strategy_coin::StrategyCoin;
    use aptos_framework::aptos_coin::AptosCoin;

    // vault manager functions

    /// approves the strategy on Vault<AptosCoin>
    /// * vault_manager: &signer - must have the vault manager role for Vault<AptosCoin>
    /// * debt_ratio: u64 - in BPS
    public entry fun approve(vault_manager: &signer, debt_ratio: u64) {
        base_strategy::approve_strategy<AptosCoin, SimpleTortugaStrategy>(
            vault_manager,
            debt_ratio,
            simple_tortuga_strategy::get_strategy_witness()
        );
    }

    /// updates the debt ratio of the strategy on Vault<AptosCoin>
    /// * vault_manager: &signer - must have the vault manager role for Vault<AptosCoin>
    /// * debt_ratio: u64 - in BPS
    public entry fun update_debt_ratio(vault_manager: &signer, debt_ratio: u64) {
        base_strategy::update_debt_ratio<AptosCoin, SimpleTortugaStrategy>(
            vault_manager,
            debt_ratio,
            simple_tortuga_strategy::get_strategy_witness()
        );
    }

    /// sets the debt ratio of the strategy to 0
    /// * vault_manager: &signer - must have the vault manager role for Vault<AptosCoin>
    public entry fun revoke(vault_manager: &signer) {
        update_debt_ratio(vault_manager, 0);
    }

    // keeper functions

    /// harvests the strategy, recognizing any profits or losses and adjusting the strategy's position
    /// * keeper: &signer - must be the keeper for the strategy on Vault<AptosCoin>
    public entry fun harvest(keeper: &signer) {

        let product_coin_balance = satay::get_vault_balance<AptosCoin, StrategyCoin<AptosCoin, SimpleTortugaStrategy>>();
        let base_coin_balance = simple_tortuga_strategy::calc_base_coin_amount(product_coin_balance);

        let (
            to_apply,
            harvest_lock
        ) = base_strategy::open_vault_for_harvest<AptosCoin, SimpleTortugaStrategy>(
            keeper,
            base_coin_balance,
            simple_tortuga_strategy::get_strategy_witness()
        );

        let product_coins = simple_tortuga_strategy::apply(to_apply);

        let debt_payment_amount = base_strategy::get_harvest_debt_payment(&harvest_lock);
        let profit_amount = base_strategy::get_harvest_profit(&harvest_lock);

        let to_liquidate_amount = simple_tortuga_strategy::calc_product_coin_amount(debt_payment_amount + profit_amount);
        let to_liquidate = base_strategy::withdraw_strategy_coin<AptosCoin, SimpleTortugaStrategy>(
            &harvest_lock,
            to_liquidate_amount
        );

        let base_coins = simple_tortuga_strategy::liquidate(to_liquidate);
        let debt_payment = coin::extract(&mut base_coins, debt_payment_amount);
        let profit = coin::extract_all(&mut base_coins);
        coin::destroy_zero(base_coins);

        base_strategy::close_vault_for_harvest<AptosCoin, SimpleTortugaStrategy>(
            harvest_lock,
            debt_payment,
            profit,
            product_coins,
        );
    }

    // user functions

    /// liquidate strategy position if vault does not have enough AptosCoin for amount of VaultCoin<AptosCoin>
    /// * user: &signer - must hold amount of VaultCoin<AptosCoin>
    /// * amount: u64 - the amount of VaultCoin<AptosCoin> to liquidate
    public entry fun withdraw_for_user(user: &signer, amount: u64) {
        let vault_coins = coin::withdraw<VaultCoin<AptosCoin>>(user, amount);
        let user_withdraw_lock = base_strategy::open_vault_for_user_withdraw<AptosCoin, SimpleTortugaStrategy>(
            user,
            vault_coins,
            simple_tortuga_strategy::get_strategy_witness()
        );

        let amount_needed = base_strategy::get_user_withdraw_amount_needed(&user_withdraw_lock);
        let product_coin_amount = simple_tortuga_strategy::calc_product_coin_amount(amount_needed);
        let product_coins = base_strategy::withdraw_strategy_coin_for_liquidation<AptosCoin, SimpleTortugaStrategy>(
            &user_withdraw_lock,
            product_coin_amount,
        );
        let base_coins = simple_tortuga_strategy::liquidate(product_coins);

        base_strategy::close_vault_for_user_withdraw<AptosCoin, SimpleTortugaStrategy>(user_withdraw_lock, base_coins);
    }
}