use ethers::prelude::*;
use std::convert::TryFrom;
use std::sync::Arc;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Connect to local Anvil
    let client = Provider::<Http>::try_from("http://localhost:8545")?;
    let client = Arc::new(client);

    // Anvil default private key (account 0)
    let wallet = "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
        .parse::<LocalWallet>()?;
    let client = SigningWallet::from((client, wallet.into())).await?;

    let artist = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266".parse::<Address>()?; // Anvil acc 1
    let label = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8".parse::<Address>()?;  // Anvil acc 2

    // ABI (shortened; use full from solc --abi MusicRoyalty.json)
    let abi = include_str!("MusicRoyalty.json"); // Or load from file
    let music_royalty_abi = MusicRoyalty::abi(&client);

    // Bytecode from solc --bin
    let bytecode = include_bytes!("MusicRoyalty.bin"); // Hex string "0x60806040..."

    // Deploy
    let music_royalty = MusicRoyalty::deploy(client, (artist, label))?
        .legacy()
        .send()
        .await?;
    println!("Contract deployed at: {:?}", music_royalty.address());

    // Simulate stream payment (send ETH to trigger receive())
    let payment = U256::from(1u64) << 128; // ~1 ETH in wei
    client.send_transaction(TransactionRequest::pay_to(music_royalty.address(), payment), None).await?;

    // Read artist share
    let artist_share = music_royalty.artist_share().call().await?;
    println!("Artist share: {}%", artist_share);

    Ok(())
}

// Contract bindings (generate with `forge bind` or ethers-rs CLI)
abigen!(
    MusicRoyalty,
    r#"
    [
        {"inputs":[{"internalType":"address","name":"_artist","type":"address"},{"internalType":"address","name":"_label","type":"address"}],"stateMutability":"nonpayable","type":"constructor"},
        {"inputs":[],"name":"artistShare","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"}
    ]
    "#,
);
