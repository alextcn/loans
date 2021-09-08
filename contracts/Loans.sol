// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.6;

import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Auction} from './Auction.sol';


// interface для Ломбарда
// eng. PawnShop не очень известно, слова Lombarter не существует, поэтому использую Loans

/*
    ставка по займу кем выдается?

    она фикисрованная на займ, типа взял 100 отдал 110
    или она задана на время, типа 10%/year и в зависимости от того когда отдашь нужно будет добавить X * time * 110% / 365 days

    было бы логично чтобы ставка по займу была не фиксирована а разная
    например для рискованных НФТ она должна быть выше
    а для НФТ на недвижимость ниже

    поэтому я пока loanRate сделаю частью самого Loan structure

    можно ввести минимальный процент overpayment (e.g. 1%) который будет обязан покрыть заемщик даже если захочет вернуть деньги в ту же минуту
*/

// todo: обсудить возможность авто-отмены LoanProposalParticipationAccepted после какого-то времени (но тут все равно lender должен дернуть метод) так просто не получится
// todo: обсудить как будет задаваться minBid для аукциона для истекших займов, у Дмитрия было предложение = 10% * amount, проблема тут в том а что если цены нфт упадет в 100 раз? тогда нфт никто никогда не купит за 0.1 первоначальной цены. Должен быть механизм.

/* займ */
struct Loan {
    address creator;
    EnumerableSet.AddressSet lenders;
    mapping(address /*lender*/ => uint256 /**/) lenderLoans;
    uint256 annualRateNumerator;
    uint256 amount;
    uint256 overpayment;
    uint40 loanStartTimstamp;
    uint40 loanFinishTimstamp;
    uint40 maxPeriod;
}


contract Loans {

    /* знаменатель дроби для ставки */
    uint256 constant public LOAN_ANNUAL_RATE_DENOMINATOR = 10000;


    /* предложение дать займ под залог создано */ 
    event LoanProposalCreated(
        uint256 indexed loanId,
        address creator,
        address indexed nftHub,
        uint256 indexed nftId,
        uint256 loanAmount,
        uint256 loanAnnualRateNumerator,
        uint40 maxPeriod
    );

    /* предложение дать займ под залог отменено */ 
    event LoanProposalCanceled(
        uint256 indexed loanId
    );

    /* предложение дать займ под залог принято одним займодателем */ 
    event LoanProposalParticipationAccepted(
        uint256 indexed loanId, 
        address indexed lender, 
        uint256 tokenAmount
    );

    /* предложение дать займ под залог принято одним займодателем но кол-во токенов которое он готов от своего лица дать изменилось */ 
    event LoanProposalParticipationChanged(
        uint256 indexed loanId, 
        address indexed lender, 
        uint256 tokenAmount
    );

    /* предложение дать займ под залог отклонено займодателем (который ранее его принял) */ 
    event LoanProposalParticipationCanceled(
        uint256 indexed loanId, 
        address indexed lender
    );

    /* займ был выдан пользователю, токены готовы к выводу */
    event LoanGiven(
        uint256 indexed loanId
    );

    /* creator забрал свой займ */
    event GivenLoanWithdrawn(
        uint256 indexed loanId
    );

    /* creator вернул займ с процентами */ 
    event LoanReturned(
        uint256 indexed,
        uint256 loanPeriod,
        uint256 overpayment  // = loanPeriod * loanAmount * loanAnnualRateNumerator / 365 days / LOAN_ANNUAL_RATE_DENOMINATOR
    );

    /* реестр всех займов */
    mapping (uint256 /*loanId*/ => Loan) internal _loans;
    /* платежный токен которым производятся все выплаты (например USDT) */
    IERC20 public immutable payableToken;
    /* контракт аукциона на который будет выставлен залог если заемщик вовремя не вернет долг */
    Auction public immutable auction;

    /* получить инфу по займу (до выдачи / после выдачи / отмененному / ликвидированному итп) */
    function getLoan(uint256 loanId) external view returns(
        address creator,
        uint256 annualRateNumerator,
        uint256 amount,
        uint256 overpayment,
        uint40 loanStartTimstamp,
        uint40 loanFinishTimstamp,
        uint40 maxPeriod
    ) {
        Loan storage loan = _loans[loanId];
        // TODO: implement
        return (address(0), 0, 0, 0, 0, 0, 0);
    }

    /* список всех заемщиков */
    function getLoanLenders(uint256 loanId) external view returns(address[] memory lenders) {
        // TODO: implement
        return lenders;
    }

    /* кол-во займа от заемщика */
    function getLoanLenderLoan(uint256 loanId, address lender) external view returns(uint256) {
        // TODO: implement
        return 0;
    }

    constructor(
        address _payableToken,
        address _auction
    ) {
        require(_payableToken != address(0), "ZERO_ADDRESS");
        require(_auction != address(0), "ZERO_ADDRESS");

        payableToken = IERC20(_payableToken);
        auction = Auction(_auction);
    }

    /* создать предложение получить займ под залог */
    function createLoanProposal(
        IERC721 nftHub, 
        uint256 nftId, 
        uint256 amount,
        uint256 annualRateNumerator,
        uint40 maxPeriod
    ) external {
        // TODO: implement
    }

    /*
        вот здесь непонятно, толи creator должен раскошелиться и потратить свой газ чтобы вернуть токены на балансы тем юзерам что уже приняли proposal толи это все так должны сделать сами юзеры,
        можно при создании proposal обязать также creator переводить немного газа который будет потом начислен lenders для возмещения газа, в случае если creator отменит proposal
    */
    /* отменить свое предложение взять займ под залог */
    function cancelLoanProposal(uint256 loanId) external {
        // TODO: implement
    }

    /* дать токенов на Лоан-пропозал, когда лендеров наберется достаточно количество, отдать их creator и за-emit-ить LoanGiven */
    function acceptProposalParticipation(uint256 loanId, uint256 amountToGive) external {
        // TODO: implement
    }

    /* меняет колво токенов который готов дать данный лендер на этот пропозал */
    function changeProposalParticipation(uint256 loanId, uint256 amountToGive) external {
        // TODO: implement
    }

    /* возвращает деньги lender по неначатому или отмененному proposal */
    function cancelProposalParticipation(uint256 loanId) external {
        // TODO: implement
    }

    /* вернуть займ (с процентами) */
    /* todo: think что если транзакция будет исполнена значительно позже? нужен ли аргумент maxOverpayment? */
    function returnLoan(uint256 loanId) external {
        // TODO: implement
    }

    //   конечно удобнее всего было бы заставить creator платить газ за то чтобы послать каждом lender его кусок токенов
    //   но это анти-паттерн и это много газа поэтому мы делаем метод чтобы лендер мог вывести свой кусок
    //  забрать свою долю токенов по возвращенному (либо ликвидированному) займу вместе с overpayment
    function withdrawReturnedProposalShare(uint256 loanId) external {
        // TODO: implement
    }

    // если заемщик долго не возвращает залог, то любой лендер имеет право вызвать этот метод и выставить залог на аукцион
    function liquidateCollateral(uint256 loanId) public {
        // TODO: implement
    }

    // поскольку оунером аукциона будет сам контракт, нам нужен метод чтобы проксировать claim на выйгранный аукцион
    function claimAuction(uint256 loanId) public {
        // TODO: implement
    }
}