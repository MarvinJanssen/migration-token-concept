import { ParsedTransactionResult } from "@hirosystems/clarinet-sdk";
import { Cl, ClarityValue, UIntCV, cvToValue } from "@stacks/transactions";
import { describe, expect, it } from "vitest";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const address3 = accounts.get("wallet_3")!;
const address4 = accounts.get("wallet_4")!;


const errDeprecated = 900;
const errMigrationNotComplete = 1002;
const migrationWaitPeriod = 6;

const usdc = (musdc: number) => musdc * 1000000;

const assertOkTrue = (val: ClarityValue, message?: string) => expect(val, message).toStrictEqual(Cl.ok(Cl.bool(true)));

const contractPrincipal = (contractName: string) => `${deployer}.${contractName}`;

const transferSip10 = (contractName: string, amount: number, sender: string, recipient: string) =>
  simnet.callPublicFn(contractName, 'transfer', [Cl.uint(amount), Cl.principal(sender), Cl.principal(recipient), Cl.none()], sender);

const transferInterimUsdc = (amount: number, sender: string, recipient: string) =>
  transferSip10('interim-usdc', amount, sender, recipient);

const transferFinalUsdc = (amount: number, sender: string, recipient: string) =>
  transferSip10('final-usdc', amount, sender, recipient);

const migrateInterimToFinalUsdc = (principals: string[], sender: string) =>
  simnet.callPublicFn('final-usdc', 'migrate-tokens', [Cl.list(principals.map(Cl.principal))], sender);

const getMigratedAmounts = (response: ParsedTransactionResult) =>
  cvToValue(response.result).value.map(({ value }: { value: UIntCV }) => BigInt(value.value));

function getTokenBalances(contractName: string, principals: string[]) {
  const results = principals.map(principal => simnet.callReadOnlyFn(contractName, 'get-balance', [Cl.principal(principal)], deployer));
  return results.map(response => BigInt(cvToValue(response.result).value));
}

describe("Integration test", () => {
  it("Interim token can be migrated to the final token", () => {
    // Mint some tokens for principals.
    let responses = [
      simnet.callPublicFn('interim-usdc', 'mint', [Cl.uint(usdc(1000)), Cl.principal(address1)], deployer),
      simnet.callPublicFn('interim-usdc', 'mint', [Cl.uint(usdc(2000)), Cl.principal(address2)], deployer),
      simnet.callPublicFn('interim-usdc', 'mint', [Cl.uint(usdc(3000)), Cl.principal(address3)], deployer),
      simnet.callPublicFn('interim-usdc', 'mint', [Cl.uint(usdc(4000)), Cl.principal(address4)], deployer),
      simnet.callPublicFn('interim-usdc', 'mint', [Cl.uint(usdc(5000)), Cl.principal(contractPrincipal('example-vault'))], deployer)
    ];
    responses.map(({ result }) => assertOkTrue(result));

    // Advance some blocks.
    simnet.mineEmptyBlocks(40);

    // Transfer some USDC around
    responses = [
      transferInterimUsdc(usdc(50), address1, address2),
      transferInterimUsdc(usdc(150), address2, address3),
      transferInterimUsdc(usdc(250), address3, address4),
      transferInterimUsdc(usdc(350), address4, contractPrincipal('example-vault'))
    ];
    responses.map(({ result }) => assertOkTrue(result));

    // Get all interim USDC token balances
    const interimBalances = getTokenBalances('interim-usdc', [address1, address2, address3, address4, contractPrincipal('example-vault')]);
    console.log('Interim balances: ', interimBalances);

    // Advance some more blocks.
    simnet.mineEmptyBlocks(40);

    // Get the total interim USDC supply
    let response = simnet.callReadOnlyFn('interim-usdc', 'get-total-supply', [], deployer);
    const totalInterimSupply = cvToValue(response.result).value;
    console.log(`Total interim USDC supply`, totalInterimSupply);

    // Trigger the migration, only the contract owner of the interim
    // USDC contract can do this. The definition of the contract owner
    // is out of the scope of the concept. (DAO, multisig, etc..)
    response = simnet.callPublicFn('interim-usdc', 'start-migration', [Cl.some(Cl.stringUtf8("https://token.uri/deprecated")), Cl.principal(contractPrincipal('final-usdc'))], deployer);
    assertOkTrue(response.result);

    // Get the total migration snapshot supply.
    response = simnet.callReadOnlyFn('interim-usdc', 'get-total-supply', [], deployer);
    const migrationSnapshotSupply = cvToValue(response.result).value;
    expect(migrationSnapshotSupply).toBe(totalInterimSupply);

    // Advance one block.
    simnet.mineEmptyBlocks(1);

    // Verify that transfers on the interim contract are no longer possible.
    response = transferInterimUsdc(usdc(50), address1, address2);
    expect(response.result).toStrictEqual(Cl.error(Cl.uint(errDeprecated)));

    // Verify that minting is no longer possible.
    response = simnet.callPublicFn('interim-usdc', 'mint', [Cl.uint(usdc(5000)), Cl.principal(address1)], deployer);
    expect(response.result).toStrictEqual(Cl.error(Cl.uint(errDeprecated)));

    // Advance a number of blocks equal to the migration wait period.
    simnet.mineEmptyBlocks(migrationWaitPeriod);

    // Migrate some principals. (Not all.) Deployer calling.
    response = migrateInterimToFinalUsdc([address1, address2], deployer);
    let migratedAmounts = getMigratedAmounts(response);
    console.log('Migrated amounts', migratedAmounts);

    // Check that final USDC cannot yet be transferred because the migration
    // is not yet complete.
    response = transferFinalUsdc(usdc(10), address1, address2);
    expect(response.result).toStrictEqual(Cl.error(Cl.uint(errMigrationNotComplete)));

    // Migrate the remaining principals. Note that anyone can call the function.
    response = migrateInterimToFinalUsdc([address3, address4, contractPrincipal('example-vault')], address1);
    migratedAmounts = getMigratedAmounts(response);
    console.log('Migrated amounts', migratedAmounts);

    // Get final USDC balances.
    const finalBalances = getTokenBalances('final-usdc', [address1, address2, address3, address4, contractPrincipal('example-vault')]);
    console.log('Final balances', finalBalances);
    expect(finalBalances).toStrictEqual(interimBalances);

    // Check that the migration is complete.

    // Final USDC can be transferred now.
    response = transferFinalUsdc(usdc(10), address1, address2);
    assertOkTrue(response.result);

    // Check if the total supply of final USDC is equal to the interim snapshot USDC supply.
    response = simnet.callReadOnlyFn('final-usdc', 'get-total-supply', [], deployer);
    const finalUsdcSupply = cvToValue(response.result).value;
    expect(finalUsdcSupply).toBe(totalInterimSupply);

    // Check that all balances of the interim token are zero.

    const interimBalancesAfterMigration = getTokenBalances('interim-usdc', [address1, address2, address3, address4, contractPrincipal('example-vault')]);
    interimBalancesAfterMigration.map(balance => expect(balance).toBe(0n));
  });
});
