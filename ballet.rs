#[derive(Accounts)]
pub struct DelegateAuctioneer<'info> {
    // Auction House instance PDA account.
    #[account(
        mut,
        seeds = [
            PREFIX.as_bytes(),
            auction_house.creator.as_ref(),
            auction_house.treasury_mint.as_ref()
        ],
        bump=auction_house.bump,
        has_one=authority
    )]
    pub auction_house: Account<'info, AuctionHouse>,

    #[account(mut)]
    pub authority: Signer<'info>,

    /// CHECK: The auction house authority can set this to whatever external address they wish.
    /// The auctioneer authority - the program PDA running this auction.
    pub auctioneer_authority: UncheckedAccount<'info>,

    /// The auctioneer PDA owned by Auction House storing scopes.
    #[account(
        init,
        payer = authority,
        space = AUCTIONEER_SIZE,
        seeds = [
            AUCTIONEER.as_bytes(),
            auction_house.key().as_ref(),
            auctioneer_authority.key().as_ref()
        ],
        bump
    )]
    pub ah_auctioneer_pda: Account<'info, Auctioneer>,

    pub system_program: Program<'info, System>,
}
